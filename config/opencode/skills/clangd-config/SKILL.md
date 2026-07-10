---
name: clangd-config
description: >
  Generate and iterate a .clangd config for C/C++ projects. Use when the user
  mentions clangd, .clangd, compile_commands.json, C/C++ language server
  setup, non-gcc/clang compiler flag translation (GHS, IAR, armclang), or
  clangd reporting too many errors/warnings.
---

# clangd-config

Generate a `.clangd` config for a C/C++ project, then run a full scan over
every file in `compile_commands.json` and iterate the config until errors and
warnings converge.

## When to trigger

- User says "generate .clangd", "configure clangd", "clangd shows too many errors"
- Project has `compile_commands.json` but clangd fails to parse sources
- Project uses a non-gcc/clang compiler (GHS ccthumb/ccarm, IAR iccarm,
  ARM armclang, MSVC cl, NVIDIA nvc)

## Pre-checks

1. `compile_commands.json` present? If not, guide the user to generate it:
   - make-based project with gcc/clang: `compiledb make` or `bear -- make`
   - make-based project with non-gcc/clang compiler (compiledb/bear cannot
     recognize it): run `make -Bn` and parse the output with a python script
     that extracts `<compiler> ... -c <source> ... -o <obj>` lines
2. clangd installed? Check in this order: mason (`~/.local/share/nvim/mason/bin/clangd`),
   brew (`/home/linuxbrew/.linuxbrew/bin/clangd`), system (`/usr/bin/clangd`).
   Prefer mason if present.
3. Compiler type? Read the first entry in `compile_commands.json`, look at
   argv[0] (the compiler path):
   - `ccthumb` / `ccarm` / `ccppc` / `cxarm` -> GHS
   - `iccarm` / `iccarm.exe` -> IAR
   - `armclang` / `armclang++` -> armclang (clang-based)
   - `gcc` / `g++` / `cc` -> gcc
   - `clang` / `clang++` -> clang (no translation needed)
   - `cl.exe` -> MSVC
   - `nvc` / `nvc++` / `pgc++` -> NVIDIA HPC

## Phase 1: Generate initial .clangd

### 1.1 Compiler flag translation

Read 5-10 entries from `compile_commands.json` and collect all flags that are
not `-I`, `-D`, `-o`, `-c`, or source files. Translate them per the tables
below. Flags not in the table are left as-is (clang will ignore unknown flags
or warn; the scan phase will catch them).

#### GHS (ccthumb / ccarm / ccppc / cxarm)

| GHS flag                    | clang equivalent  | action       |
| --------------------------- | ----------------- | ------------ |
| `-cpu=cortexm7`               | `-mcpu=cortex-m7`   | Remove + Add |
| `-cpu=cortexm4`               | `-mcpu=cortex-m4`   | Remove + Add |
| `-thumb`                      | `-mthumb`           | Remove + Add |
| `-c99`                        | `-std=c99`          | Remove + Add |
| `-c11`                        | `-std=c11`          | Remove + Add |
| `-Osize`                      | `-Os`               | Remove + Add |
| `-ansi`                       | (none)            | Remove       |
| `--ghstd=*`                   | (none)            | Remove       |
| `--gnu_asm`                   | (none)            | Remove       |
| `--unsigned_chars`            | `-funsigned-char`   | Remove + Add |
| `--unsigned_fields`           | (none)            | Remove       |
| `--no_exceptions`             | `-fno-exceptions`   | Remove + Add |
| `--no_commons`                | `-fno-common`       | Remove + Add |
| `--short_enum`                | `-fshort-enums`     | Remove + Add |
| `-G`                          | (none)            | Remove       |
| `-preprocess_assembly_files`  | (none)            | Remove       |
| `-dual_debug`                 | (none)            | Remove       |
| `--prototype_errors`          | (none)            | Remove       |
| `-nostartfile`                | (none)            | Remove       |
| `--incorrect_pragma_warnings` | (none)            | Remove       |
| `-keeptempfiles`              | (none)            | Remove       |
| `-list`                       | (none)            | Remove       |

Note: GHS uses two `-c` flags in one command. The first `-c` means
"compile only" (followed by `-Osize`), the second `-c` precedes the source
file. clang's `-c` is single-purpose; keep only the second one and rely on
`-fsyntax-only` semantics from clangd.

#### IAR (iccarm)

| IAR flag              | clang equivalent     | action       |
| --------------------- | -------------------- | ------------ |
| `--cpu=cortex-m4`       | `-mcpu=cortex-m4`      | Remove + Add |
| `--cpu=cortex-m7`       | `-mcpu=cortex-m7`      | Remove + Add |
| `--thumb`               | `-mthumb`              | Remove + Add |
| `--c99`                 | `-std=c99`             | Remove + Add |
| `--c11`                 | `-std=c11`             | Remove + Add |
| `-Ohz` (size)           | `-Os`                  | Remove + Add |
| `-Oh` (high)            | `-O2`                  | Remove + Add |
| `--dlib_config=*`       | (none)               | Remove       |
| `--vla`                 | (none, clang default) | Remove       |
| `--no_wrap_diagnostics` | (none)               | Remove       |
| `--misra2004=*`         | (none)               | Remove       |
| `--diag_suppress=*`     | `-Wno-*` (manual)      | Remove       |

#### armclang (clang-based)

armclang is clang under the hood. Most flags already match clang. Only remove
armclang-specific extras:

| armclang flag     | action                  |
| ----------------- | ----------------------- |
| `--library_type=*`  | Remove                  |
| `--depend=*`        | Remove                  |
| `--depend_format=*` | Remove                  |
| `--apcs=*`          | Remove                  |
| `--cpu=*`           | Remove + Add `-mcpu=*`    |
| `--fpu=*`           | Remove + Add `-mfpu=*`    |

#### gcc / clang

No translation needed. Skip to phase 2.

### 1.2 Target triple inference

From the translated `-mcpu` and `-mthumb`, build the target:

```
--target=arm-none-eabi -mcpu=cortex-m7 -mthumb
```

For non-ARM targets (x86_64, RISC-V), omit `--target` or set it to the
matching triple (e.g. `riscv64-unknown-elf`).

### 1.3 Standard library headers

Non-gcc/clang compilers ship their own C standard library headers (stdio.h,
string.h, stdlib.h, stdint.h, stdarg.h, stddef.h, stdbool.h). clangd needs
to find them.

- **GHS**: headers at `<ghs_install>/ansi/`. Use `-idirafter` (NOT `-isystem`)
  so clang's own freestanding headers (stdint.h, stdarg.h, stddef.h) win.
  GHS's stdint.h uses `#if __CHAR_BIT==8` guards that need GHS-specific
  predefined macros; clang's freestanding stdint.h avoids this entirely.
- **IAR**: headers at `<iar_install>/inc/`. Use `-idirafter`.
- **armclang**: uses clang's own headers. No extra path needed.

Add `-ffreestanding` to make clang use its own freestanding headers for
`stdint.h` / `stdarg.h` / `stddef.h` / `stdbool.h` and only fall back to the
compiler vendor's headers for `stdio.h` / `string.h` / `stdlib.h`.

### 1.4 Predefined macros

Some vendor headers depend on compiler-specific predefined macros. Query them
and add the needed ones as `-D`:

```bash
# Create an empty .c file, then:
<compiler> -E -dM empty.c   # GHS needs a real file, not stdin
```

Common macros that vendor headers check for:

| Macro               | Vendor | Why needed                                             |
| ------------------- | ------ | ------------------------------------------------------ |
| `__ghs__`             | GHS    | GHS headers gate `#pragma ghs` blocks                    |
| `__CHAR_BIT`          | GHS    | GHS stdint.h: `#if __CHAR_BIT==8` selects int8_t typedef |
| `__INT_BIT`           | GHS    | GHS stdint.h: selects int16_t/int32_t                  |
| `__LONG_BIT`          | GHS    | GHS stdint.h: selects int32_t typedef                  |
| `__SHRT_BIT`          | GHS    | GHS stdint.h: selects int16_t typedef                  |
| `__LLONG_BIT`         | GHS    | GHS stdint.h: selects int64_t typedef                  |
| `__IAR_SYSTEMS_ICC__` | IAR    | IAR headers gate vendor extensions                     |

When using `-ffreestanding` + clang's own stdint.h (recommended for GHS),
the `__CHAR_BIT` family is NOT needed — only `__ghs__` (for `#pragma ghs`
and other vendor-specific gates in non-stdint headers).

### 1.5 Initial template

```yaml
# clangd configuration (generated by clangd-config skill)
CompileFlags:
  Compiler: clang
  Add:
    - --target=<triple>
    - -mcpu=<cpu>
    - -mthumb              # remove if not ARM Thumb
    - -std=<c99|c11|gnu99>
    - -fshort-enums        # if vendor uses short enums (GHS --short_enum)
    - -funsigned-char      # if vendor defaults to unsigned char (GHS)
    - -fno-common          # if vendor sets --no_commons
    - -fno-exceptions      # C project
    - -ffreestanding       # embedded / bare-metal
    - -idirafter
    - <vendor_stdlib_path>
    - -D_CLANGD=1
    - <vendor_predefined_macros>
  Remove:
    - <vendor_flags_to_strip>
Index:
  Background: Build
Diagnostics:
  MissingIncludes: None
  ClangTidy:
    Add: [bugprone-*, performance-*, readability-*]
    Remove: [modernize-use-trailing-return-type, readability-identifier-naming]
InlayHints:
  Enabled: Yes
  ParameterNames: Yes
  DeducedTypes: Yes
```

## Phase 2: Full scan

Run the scan script bundled with this skill:

```bash
python3 <skill_dir>/scan.py <project_root>                # auto-detect parallelism
python3 <skill_dir>/scan.py <project_root> --jobs 4       # force 4 workers
python3 <skill_dir>/scan.py <project_root> --jobs 1       # serial (debug)
```

The script auto-detects a safe number of parallel clangd workers based on
available memory (each worker peaks at ~500 MB; reserve 1 GB for the system;
cap at 8). For a 5000-file project with 8 workers, scan time is ~2 minutes
instead of ~15 minutes serial. If workers get OOM-killed, the report shows
`OOM killed: N (try lowering --jobs)` — re-run with a lower `--jobs` value.

The script:
- reads `compile_commands.json` from `<project_root>`
- finds clangd (mason > brew > system)
- runs `clangd --check=<file> --check-lines=1` on every file (parallel)
- parses `E[...]` and `W[...]` lines, groups by diagnostic category
- optionally samples files and runs `clang-tidy` for clang-tidy check warnings
- prints a structured report

Output format:

```
=== Scan complete: 410 files ===
Total errors: 153 (files with errors: 41)
Total warnings: 0

=== Error categories (5) ===
  expected_lparen_after: 36  | example: SchM_Adc.c: expected '(' after 'asm'
  undeclared_var_use: 36     | example: SchM_Adc.c: use of undeclared identifier 'mrs'
  -Wimplicit-function-declaration: 5 | example: Bootloader.c: call to undeclared function 'console_write'
  -Wincompatible-pointer-types: 3   | example: CryptoDal_Crypto.c: incompatible pointer types
  -Wint-conversion: 1         | example: Rte.c: incompatible integer to pointer conversion

=== Files with errors ===
  .../SchM_Adc.c: 4 errors
  .../Bootloader.c: 1 errors
  ...

=== Warning categories (0) ===
  (none)
```

## Phase 3: Iterate (fully automatic)

After each scan, apply the decision tree below, edit `.clangd`, then re-scan.
Repeat until errors stop decreasing (convergence).

### Decision tree

For each error/warning category:

```
Compile error?
  +-- unknown command line argument
  |     -> add the flag to CompileFlags.Remove
  +-- unknown type name (uint8_t, uint32_t, ...)
  |     -> check if -ffreestanding is set; if not, add it
  |     -> if already set, check if vendor stdint.h is being used instead of
  |        clang's; switch -isystem to -idirafter for the vendor header path
  |     -> if still failing, query vendor predefined macros (__CHAR_BIT etc.)
  |        and add them as -D
  +-- asm / inline assembly syntax error (expected '(' after 'asm',
  |   use of undeclared identifier 'mrs', redefinition of function)
  |     -> ACCEPT. This is vendor-specific assembly syntax (GHS __asm function
  |        bodies, IAR #pragma). clang cannot parse it. List in the final
  |        report as "unfixable: vendor asm syntax". These files still work
  |        for navigation outside the asm blocks.
  +-- implicit function declaration (-Wimplicit-function-declaration)
  |     -> add -Wno-implicit-function-declaration to CompileFlags.Add
  |     -> note: this is a real code defect (missing #include) but common in
  |        legacy AUTOSAR code; suppress to keep the IDE usable
  +-- incompatible pointer types (-Wincompatible-pointer-types)
  |     -> add -Wno-incompatible-pointer-types
  +-- integer to pointer conversion (-Wint-conversion)
  |     -> add -Wno-int-conversion
  +-- integer to pointer cast (-Wint-to-pointer-cast)
  |     -> add -Wno-int-to-pointer-cast
  +-- pragma pack modified (-Wpragma-pack)
  |     -> add -Wno-pragma-pack
  +-- macro redefined (-Wmacro-redefined)
  |     -> add -Wno-macro-redefined
  +-- undefined macro in #if (-Wundef)
  |     -> add -Wno-undef
  +-- other
        -> analyze manually, decide per-case

Clang-tidy warning?
  +-- readability-magic-numbers
  |     -> add to ClangTidy.Remove (embedded code uses register addresses as literals)
  +-- performance-no-int-to-ptr
  |     -> add to ClangTidy.Remove (register access via pointer casts)
  +-- bugprone-easily-swappable-parameters
  |     -> add to ClangTidy.Remove (AUTOSAR APIs have similar-typed params by spec)
  +-- readability-uppercase-literal-suffix
  |     -> add to ClangTidy.Remove (AUTOSAR style uses lowercase u/U suffix)
  +-- readability-identifier-length
  |     -> add to ClangTidy.Remove (loop vars i, j, k are standard)
  +-- readability-braces-around-statements
  |     -> add to ClangTidy.Remove (style preference, not a bug)
  +-- readability-else-after-return
  |     -> add to ClangTidy.Remove (style preference)
  +-- bugprone-branch-clone
  |     -> add to ClangTidy.Remove (common in generated AUTOSAR code)
  +-- modernize-use-trailing-return-type
  |     -> add to ClangTidy.Remove (C does not use trailing return types)
  +-- readability-identifier-naming
  |     -> add to ClangTidy.Remove (AUTOSAR has its own naming convention)
  +-- other
        -> keep if it catches real bugs; suppress if it is noise for embedded
```

### Convergence

Stop iterating when:
- errors == 0, OR
- remaining errors are all in the "vendor asm syntax" category (unfixable), OR
- two consecutive scans produce the same error count (no progress)

### What NOT to suppress

- Real type errors that indicate bugs (do not blanket `-w` to silence everything)
- Missing includes that the user might want to fix (use `MissingIncludes: None`
  to hide the diagnostic, but mention them in the report)

## Phase 4: Deliverables

After convergence, output:

1. **Final `.clangd`** — the complete file content
2. **Before/after table** — error count, warning count, files-with-errors count
3. **Unfixable list** — files with remaining errors, grouped by reason:
   - "vendor asm syntax (GHS __asm / IAR #pragma): N files"
   - "real code defect (missing #include): N files, list them"
4. **Warning category table** — category, count, suppression method

## Notes

- Always use `-idirafter` (not `-isystem`) for vendor standard library paths
  when `-ffreestanding` is also set. This lets clang's own freestanding
  stdint.h/stdarg.h/stddef.h win, avoiding vendor-macro dependencies.
- Do NOT add `-D__ghs__=1` blindly. Only add vendor predefined macros that the
  vendor's own headers actually check for. Run `compiler -E -dM` to find them.
- The scan script uses `--check=<file>` (with `=`, not space). clangd rejects
  the space-separated form.
- clangd `--check` mode does NOT run clang-tidy. To see clang-tidy warnings,
  the scan script samples files and runs `clang-tidy` directly.
- For AUTOSAR / MISRA / embedded projects, most clang-tidy `readability-*`
  and `bugprone-*` checks are noise. Suppress aggressively.
