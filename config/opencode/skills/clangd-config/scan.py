#!/usr/bin/env python3
"""Scan all files in compile_commands.json with clangd --check.

Usage:
    python3 scan.py [project_root] [--clangd PATH] [--tidy] [--json] [--jobs N]

Outputs a structured report of errors and warnings grouped by category.
Exit code 0 if no errors, 1 otherwise.
"""
import argparse
import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

# Regex for clangd --check diagnostic lines:
#   E[19:03:21.411] [category] Line N: message
#   W[19:03:21.411] [-Wcategory] Line N: message
DIAG_RE = re.compile(r'^([EW])\[\d+:\d+:\d+\.\d+\]\s+\[([^\]]+)\]')

# Regex for clang-tidy output lines:
#   file:line:col: warning: message [check-name]
TIDY_RE = re.compile(r'warning:\s+(.+?)\s+\[([a-z0-9_.-]+)\]')


def find_clangd():
    """Find clangd binary. Order: mason > brew > system."""
    candidates = [
        os.path.expanduser('~/.local/share/nvim/mason/bin/clangd'),
        '/home/linuxbrew/.linuxbrew/bin/clangd',
        '/usr/bin/clangd',
        '/usr/local/bin/clangd',
    ]
    for c in candidates:
        if os.path.isfile(c) and os.access(c, os.X_OK):
            return c
    # fallback: search PATH
    for d in os.environ.get('PATH', '').split(':'):
        p = os.path.join(d, 'clangd')
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return None


def find_tidy():
    """Find clang-tidy binary on PATH or common locations."""
    for d in os.environ.get('PATH', '').split(':'):
        p = os.path.join(d, 'clang-tidy')
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return None


def find_compile_db(project_root):
    """Locate compile_commands.json in or above project_root."""
    p = Path(project_root).resolve()
    while True:
        candidate = p / 'compile_commands.json'
        if candidate.is_file():
            return str(candidate)
        if p.parent == p:
            return None
        p = p.parent


def auto_detect_jobs():
    """Pick a safe number of parallel clangd workers.

    Each clangd --check process peaks at ~500 MB RAM. Reserve 1 GB for the
    system and the editor, then divide the rest by 500 MB. Cap at 8 to avoid
    excessive context-switching, and never exceed CPU count.
    """
    cpu = os.cpu_count() or 1

    avail_mb = 0
    try:
        with open('/proc/meminfo') as f:
            for line in f:
                if line.startswith('MemAvailable:'):
                    avail_mb = int(line.split()[1]) // 1024  # kB -> MB
                    break
    except Exception:
        avail_mb = 2048  # fallback: assume 2 GB

    safe_mb = max(avail_mb - 1024, 512)
    mem_jobs = max(1, safe_mb // 500)
    return min(cpu, mem_jobs, 8)


def run_clangd_check(clangd_bin, filepath, cwd, timeout=30):
    """Run clangd --check on one file. Return (stdout+stderr, error_or_None).

    error is None on success, 'TIMEOUT' on timeout, 'SIGKILL' if the process
    was killed (likely OOM), or 'SIGNAL' for other signal deaths.
    """
    try:
        result = subprocess.run(
            [clangd_bin, '--check=' + filepath, '--check-lines=1'],
            capture_output=True, text=True, timeout=timeout, cwd=cwd,
        )
        if result.returncode < 0:
            return '', 'SIGKILL' if result.returncode == -9 else 'SIGNAL'
        return result.stderr + result.stdout, None
    except subprocess.TimeoutExpired:
        return '', 'TIMEOUT'
    except Exception as e:
        return '', str(e)


def parse_clangd_output(output):
    """Parse clangd --check output. Return list of (level, category, line)."""
    diags = []
    for line in output.split('\n'):
        m = DIAG_RE.match(line)
        if m:
            level = m.group(1)  # 'E' or 'W'
            category = m.group(2)
            diags.append((level, category, line))
    return diags


def run_tidy_sample(tidy_bin, filepath, db_dir, checks, timeout=60):
    """Run clang-tidy on one file. Return list of (category, message)."""
    try:
        result = subprocess.run(
            [tidy_bin, filepath, '--checks=' + checks, '-p', db_dir],
            capture_output=True, text=True, timeout=timeout,
        )
        out = result.stdout
    except subprocess.TimeoutExpired:
        return []
    except Exception:
        return []
    findings = []
    for line in out.split('\n'):
        m = TIDY_RE.search(line)
        if m:
            findings.append((m.group(2), m.group(1)))
    return findings


def scan(project_root, clangd_bin, do_tidy=False, json_out=False, jobs=1):
    db_path = find_compile_db(project_root)
    if not db_path:
        print('ERROR: compile_commands.json not found in or above ' + project_root,
              file=sys.stderr)
        return 1
    db_dir = os.path.dirname(db_path)

    with open(db_path) as f:
        entries = json.load(f)

    total = len(entries)
    error_files = []          # list of (file, count)
    error_cats = defaultdict(lambda: {'count': 0, 'example': ''})
    warning_cats = defaultdict(lambda: {'count': 0, 'example': ''})
    tidy_cats = defaultdict(lambda: {'count': 0, 'example': ''})
    errors_total = 0
    warnings_total = 0
    timeouts = 0
    oom_killed = 0

    tidy_bin = find_tidy() if do_tidy else None
    tidy_checks = ('bugprone-*,performance-*,readability-*,'
                   '-modernize-use-trailing-return-type,'
                   '-readability-identifier-naming')

    # Phase 1: collect raw results from clangd --check
    # Each result is (index, filepath, output, err)
    results = []

    if jobs <= 1:
        # Serial mode
        for i, entry in enumerate(entries):
            f = entry['file']
            output, err = run_clangd_check(clangd_bin, f, db_dir)
            results.append((i, f, output, err))
            if (i + 1) % 50 == 0:
                print('  progress: %d/%d...' % (i + 1, total), file=sys.stderr)
    else:
        # Parallel mode
        with ProcessPoolExecutor(max_workers=jobs) as pool:
            future_to_task = {
                pool.submit(run_clangd_check, clangd_bin, entry['file'], db_dir): (i, entry['file'])
                for i, entry in enumerate(entries)
            }
            completed = 0
            for future in as_completed(future_to_task):
                i, f = future_to_task[future]
                try:
                    output, err = future.result()
                except Exception as e:
                    output, err = '', 'EXCEPTION: ' + str(e)
                results.append((i, f, output, err))
                completed += 1
                if completed % 50 == 0:
                    print('  progress: %d/%d...' % (completed, total), file=sys.stderr)

    # Phase 2: process results (single code path for both modes)
    results.sort(key=lambda x: x[0])
    for i, f, output, err in results:
        if err:
            if err == 'TIMEOUT':
                timeouts += 1
                error_files.append((f, 'TIMEOUT'))
            elif err in ('SIGKILL', 'SIGNAL'):
                oom_killed += 1
                error_files.append((f, 'OOM_KILLED'))
            else:
                error_files.append((f, err))
            continue

        diags = parse_clangd_output(output)
        file_errors = 0
        for level, cat, line in diags:
            if level == 'E':
                file_errors += 1
                errors_total += 1
                error_cats[cat]['count'] += 1
                if not error_cats[cat]['example']:
                    parts = line.split('] ', 2)
                    msg = parts[-1][:100] if len(parts) > 2 else ''
                    error_cats[cat]['example'] = os.path.basename(f) + ': ' + msg
            else:
                warnings_total += 1
                warning_cats[cat]['count'] += 1
                if not warning_cats[cat]['example']:
                    parts = line.split('] ', 2)
                    msg = parts[-1][:100] if len(parts) > 2 else ''
                    warning_cats[cat]['example'] = os.path.basename(f) + ': ' + msg

        if file_errors > 0:
            error_files.append((f, file_errors))

        # clang-tidy sampling: every 80th file, run in main process (serial)
        if do_tidy and tidy_bin and i % 80 == 0:
            findings = run_tidy_sample(tidy_bin, f, db_dir, tidy_checks)
            for cat, msg in findings:
                tidy_cats[cat]['count'] += 1
                if not tidy_cats[cat]['example']:
                    tidy_cats[cat]['example'] = os.path.basename(f) + ': ' + msg[:100]

    if json_out:
        report = {
            'total_files': total,
            'errors_total': errors_total,
            'warnings_total': warnings_total,
            'files_with_errors': len(error_files),
            'timeouts': timeouts,
            'oom_killed': oom_killed,
            'error_categories': dict(error_cats),
            'warning_categories': dict(warning_cats),
            'tidy_categories': dict(tidy_cats),
            'error_files': [(f, c) for f, c in error_files],
        }
        print(json.dumps(report, indent=2))
    else:
        print()
        print('=== Scan complete: %d files ===' % total)
        print('Total errors: %d (files with errors: %d)' %
              (errors_total, len(error_files)))
        print('Total warnings: %d' % warnings_total)
        if timeouts:
            print('Timeouts: %d' % timeouts)
        if oom_killed:
            print('OOM killed: %d (try lowering --jobs)' % oom_killed)

        if error_cats:
            print()
            print('=== Error categories (%d) ===' % len(error_cats))
            for cat, info in sorted(error_cats.items(),
                                    key=lambda x: -x[1]['count']):
                print('  %s: %d  | %s' % (cat, info['count'], info['example']))

        if error_files:
            print()
            print('=== Files with errors ===')
            for f, c in error_files:
                print('  %s: %s errors' % (f, c))

        if warning_cats:
            print()
            print('=== Warning categories (%d) ===' % len(warning_cats))
            for cat, info in sorted(warning_cats.items(),
                                    key=lambda x: -x[1]['count']):
                print('  %s: %d  | %s' % (cat, info['count'], info['example']))

        if tidy_cats:
            print()
            print('=== Clang-tidy categories (%d, sampled) ===' %
                  len(tidy_cats))
            for cat, info in sorted(tidy_cats.items(),
                                    key=lambda x: -x[1]['count']):
                print('  %s: %d  | %s' % (cat, info['count'], info['example']))

    return 1 if errors_total else 0


def main():
    parser = argparse.ArgumentParser(
        description='Scan compile_commands.json with clangd --check')
    parser.add_argument('project_root', nargs='?', default='.',
                        help='project root (default: current dir)')
    parser.add_argument('--clangd', default=None,
                        help='path to clangd binary (default: auto-detect)')
    parser.add_argument('--tidy', action='store_true',
                        help='also sample clang-tidy warnings (every 80th file)')
    parser.add_argument('--jobs', type=int, default=0,
                        help='parallel workers (default: auto-detect, 0=auto, 1=serial)')
    parser.add_argument('--json', action='store_true',
                        help='output JSON instead of text')
    args = parser.parse_args()

    clangd_bin = args.clangd or find_clangd()
    if not clangd_bin:
        print('ERROR: clangd not found. Install via mason, brew, or system.',
              file=sys.stderr)
        return 2

    jobs = args.jobs
    if jobs == 0:
        jobs = auto_detect_jobs()

    print('Using clangd: %s' % clangd_bin, file=sys.stderr)
    print('Workers: %d' % jobs, file=sys.stderr)
    if args.tidy:
        print('Clang-tidy sampling enabled', file=sys.stderr)

    return scan(args.project_root, clangd_bin, do_tidy=args.tidy,
                json_out=args.json, jobs=jobs)


if __name__ == '__main__':
    sys.exit(main())
