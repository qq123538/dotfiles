# Dotfiles

Personal configuration for a Linux workstation (Ubuntu 22.04, native
bare-metal or WSL2): zsh + oh-my-zsh, Neovim (AstroNvim), tmux,
Alacritty/WezTerm, fzf/Atuin/Yazi, and the OpenCode AI coding agent.

Forked from [nicknisi/dotfiles](https://github.com/nicknisi/dotfiles), with
my own customizations layered on top.

> **Note**
> Coming from nicknisi's [vim + tmux talk](https://www.youtube.com/watch?v=5r6yzFEXajQ)? These dotfiles have changed tremendously since. Browse [the repo at recording time](https://github.com/nicknisi/dotfiles/tree/aa72bed5c4ecec540a31192581294818b69b93e2) for the version shown in the video.

## Environment model

Two host questions shape how the installer behaves — probe them on a new
machine instead of assuming.

**WSL2 or native Linux?** On Windows hosts, Alacritty and WezTerm run on the
Windows side and launch WSL via `wsl.exe`. On native Linux they run on the
same host as the shell and inherit the login shell set by `install.sh shell`.

**Local or directory-service user?** Corporate machines use AD/SSSD accounts
that are not in `/etc/passwd`. This decides how the login shell is switched —
see [Switching the shell](#switching-the-shell-tiered).

```bash
getent -s files passwd "$USER"   # returns a row → local /etc/passwd user
[ -e /run/WSL ]                  # true → running under WSL
command -v brew sss_override chsh
```

## How install works

`install.sh` is the one-stop entry point for setup, backup, and installation:

```bash
Usage: install.sh {backup|link|git|homebrew|ohmyzsh|shell|codegraph|all}
```

### Symlink model

`link` symlinks config into `$HOME`, so the repo stays the single source of
truth — editing a tracked file edits the live config.

- `**/*.symlink` → `~/.<basename>` with the suffix stripped
  (`zsh/zshrc.symlink` → `~/.zshrc`)
- each top-level entry in `config/` → `~/.config/<entry>`
  (`config/nvim` → `~/.config/nvim`)

The repo is location-independent — clone it anywhere. To add a new tool, drop
its config under `config/<tool>/` and re-run `./install.sh link`.

### Subcommands

| Command | What it does |
| ------- | ------------ |
| `backup` | Move existing dotfiles aside into `~/dotfiles-backup/` |
| `link` | Create the symlinks described above |
| `homebrew` | Install/verify Homebrew, then `brew bundle` against the [Brewfile](./Brewfile) |
| `git` | Write machine-local `~/.gitconfig-local` (identity + credential helper) |
| `ohmyzsh` | Install oh-my-zsh, powerlevel10k, and zsh-autosuggestions |
| `shell` | Switch the login shell to zsh — tiered, see below |
| `codegraph` | Install the CodeGraph CLI via its official installer |
| `all` | `link` + `homebrew` + `git` + `ohmyzsh` + `shell` + `codegraph` |

`all` does **not** run `backup` — run that manually if you have existing
dotfiles to preserve.

### Homebrew on Linux

`setup_homebrew` has three states:

1. brew absent → installs via the official script (needs `sudo` to create
   `/home/linuxbrew/.linuxbrew`)
2. brew present + prefix writable by `$USER` → runs `brew bundle` (owner)
3. brew present + prefix read-only → skips `brew bundle`, warns, and reuses
   the existing binaries via `PATH`

State 3 is Homebrew's supported multi-user model — one owner installs, others
consume. A user without `sudo` can still run `./install.sh all` when Homebrew
was already installed by someone else.

Prefix detection order is `~/brew` > `~/.linuxbrew` > `/home/linuxbrew/.linuxbrew`
(each shellenv prepends PATH, so `~/brew` is eval'd last and wins).

> **Note**
> If admin policy forbids a new top-level dir under `/home`, skip the official installer and `git clone https://github.com/Homebrew/brew ~/brew` instead. That prefix (22 chars) is shorter than the bottled one (25), so `HOMEBREW_RELOCATE_BUILD_PREFIX=1` still lets pinned bottles relocate there instead of building from source.

### Switching the shell (tiered)

`shell` probes the user type first and picks one of three paths:

1. **Local user** (in `/etc/passwd`) → `chsh -s <brew zsh>`, the standard
   path.
2. **AD/SSSD user** with `sss_override` + passwordless sudo →
   `sss_override user-add`, a per-user SSSD override that does not touch AD.
   First-time creation restarts `sssd`; subsequent updates use `sss_cache -u`
   (less disruptive).
3. **AD/SSSD user without sudo** (or no `sss_override`) → sentinel-guarded
   `~/.bashrc` block that `exec`s zsh on interactive login.

In case 3, non-interactive sessions (cron, `ssh -c`, `su -`) stay bash —
`$SHELL` is not changed. For a real change, ask your AD admin to set
`loginShell`.

`/etc/shells` is probed first (required by both `chsh` and SSSD validation).
If the brew zsh path isn't listed and sudo is unavailable, the script prints
the manual command to run.

### backup

`backup` moves every existing file that `link` would skip into
`~/dotfiles-backup/`, plus legacy vim state (`~/.vim`, `~/.vimrc`,
`~/.config/nvim`) when it is not itself a symlink.

## Quickstart

On a minimal/fresh Ubuntu image, install prerequisites first:

```bash
sudo apt update && sudo apt install -y git curl
```

Then:

```bash
git clone https://github.com/qq123538/dotfiles.git
cd dotfiles
./install.sh all
```

When the install finishes, open tmux and install its plugins with `M-s I`
(prefix `M-s`, then Shift+I).

## ZSH configuration

The ZSH setup uses [oh-my-zsh](https://ohmyz.sh/) with the
[Powerlevel10k](https://github.com/romkatv/powerlevel10k) theme.
Configuration is split across four files, each symlinked into `$HOME`:

- `zsh/zshenv.symlink` → `~/.zshenv` — sourced on every shell invocation.
  Sets `$DOTFILES` (repo root, via readlink resolution), `$CACHEDIR`,
  `$PATH`, `EDITOR`, and puts `zsh/functions/` on `fpath`.
- `zsh/zprofile.symlink` → `~/.zprofile` — sourced on login shells.
  Evaluates Homebrew shellenv (macOS arm/intel and Linuxbrew paths).
- `zsh/zshrc.symlink` → `~/.zshrc` — the main interactive config. Loads
  oh-my-zsh and p10k, then recursively sources every `$DOTFILES/**/*.zsh`.
- `zsh/p10k.zsh.symlink` → `~/.p10k.zsh` — Powerlevel10k prompt configuration
  (lean style, generated by `p10k configure`).

A new `*.zsh` file anywhere under `$DOTFILES` auto-loads on the next shell.

### ZSH plugins

Declared in `zshrc.symlink`:

- `git` — git aliases and completions
- `fzf` — fzf key bindings (`Ctrl-T` files, `Alt-C` directories)
- `zsh-autosuggestions` — fish-style inline suggestions (installed by
  `install.sh ohmyzsh`)

### Machine-local overrides

These files are sourced if present but never committed:

- `~/.zshenv.local` — environment overrides (sourced by `zshenv.symlink`)
- `~/.zshrc.local` — interactive shell overrides (sourced by `zshrc.symlink`)
- `~/.localrc` — machine-specific config (sourced by `zshrc.symlink`)
- `~/.gitconfig-local` — git identity and per-OS credential helper (written
  by `install.sh git`)

### Autoloadable functions

`zsh/functions/` is on `fpath`, providing:

- `oc` — launch the OpenCode TUI
- `occm` — generate a conventional commit message via
  `opencode run --command commit` (pass `-m <provider/model>` to select a
  model; extra args become instructions)
- `ocpr` — run the `/pr` command headlessly via `opencode run --command pr`

## Git & SSH: multi-account setup

Per-machine, manual setup. The structure lives in the repo; identity (keys,
emails, host names) stays in `$HOME` and is never committed.

### Setup steps

1. **Generate two SSH keys**:
   ```bash
   ssh-keygen -t ed25519 -C "<personal-email>" -f ~/.ssh/id_ed25519_personal
   ssh-keygen -t ed25519 -C "<work-email>"      -f ~/.ssh/id_ed25519_work
   ```

2. **Register public keys**:
   - `~/.ssh/id_ed25519_personal.pub` → GitHub Settings → SSH keys
   - `~/.ssh/id_ed25519_work.pub`     → GitLab (or work host) → SSH keys

3. **Write `~/.ssh/config`** (per-machine, not managed by dotfiles):
   ```ssh-config
   Host github.com
     HostName github.com
     User git
     IdentityFile ~/.ssh/id_ed25519_personal
     IdentitiesOnly yes

   Host <work-host>
     HostName <work-host>
     User git
     IdentityFile ~/.ssh/id_ed25519_work
     IdentitiesOnly yes

   Host *
     AddKeysToAgent yes
     IdentitiesOnly yes
   ```

4. **Set default identity** via `./install.sh git` (writes
   `~/.gitconfig-local`).

5. **Per repo, after clone** (stored in `.git/config`, never committed):
   ```bash
   git config user.name  "<name>"
   git config user.email "<email>"
   ```

### repo (multi-repo manifest) workflow

For `repo init -u ...` workflows (Android, AOSP, embedded manifests),
`repo sync` checks out dozens of projects — setting `user.email` per project
is impractical.

Use `repo init --config-name` instead: it prompts for `user.name` /
`user.email` once and writes them to `.repo/config`, inherited by every
project under that manifest.

1. **Init manifest with identity** (run once per manifest checkout):
   ```bash
   repo init -u git@<work-host>:<org>/manifest.git --config-name
   # prompts:
   #   Your Name  [Feng Li]:
   #   Your Email [feng.li37.o@nio.com]:
   ```
   Identity is stored in `.repo/manifests.git/config` (under the manifest
   checkout dir, never committed).

2. **Sync** — all projects inherit the identity from step 1:
   ```bash
   repo sync
   ```

3. **Different manifest, different identity** — each manifest checkout gets
   its own `repo init --config-name`. Personal manifest → personal email;
   work manifest → work email. No cross-contamination.

4. **Already-synced projects missing identity** (e.g. manifest added new
   projects after a sync, or `--config-name` was forgotten) — fix in bulk:
   ```bash
   repo forall -c 'git config user.email "<email>"; git config user.name "<name>"'
   ```

SSH routing is unaffected: each project's remote URL (`git@<host>:...`) is
matched against `~/.ssh/config` independently, so mixed GitHub + work-host
manifests route the right key per project automatically.

### This repo's own identity

The XDG global gitconfig (`config/git/config`) pins this repo to a personal
identity via an `includeIf hasconfig:remote.*.url:*qq123538/dotfiles*` block —
it matches by remote URL, so it survives any clone path.

Prerequisite: classic `~/.gitconfig` must not set `[user]` (it outranks XDG
and would override the include). With it absent, work identity comes from
`~/.gitconfig-local`, and this repo overrides to personal.

### Verify

```bash
ssh -T git@github.com        # → Hi <username>!
ssh -T git@<work-host>       # → Welcome to GitLab, @<username>!
cd <repo> && git config user.email                       # single repo
cd <manifest-root>/.repo/manifests.git && git config user.email  # repo manifest
cd <manifest-root>/<project> && git config user.email            # inherited
```

## Neovim setup

Neovim installs from Homebrew — already covered if you ran
`./install.sh homebrew`:

```bash
brew install neovim
```

All configuration starts at `config/nvim/init.lua`, symlinked into
`~/.config/nvim`. It bootstraps lazy.nvim, which imports the AstroNvim
community packs plus the user plugin specs in `lua/plugins/`.

> **Warning**
> The first `nvim` launch will show errors until the plugins finish installing — this is expected.

### Installing plugins

On first run, [lazy.nvim](https://github.com/folke/lazy.nvim) auto-installs
every required plugin. Interface with it via `:Lazy` inside Neovim.

Plugins are listed in [`config/nvim/lua/plugins/`](./config/nvim/lua/plugins/)
— adding a spec there is enough for lazy.nvim to pick it up.

> **Note**
> Plugins can be synced headlessly with `nvim --headless "+Lazy! sync" +qa`.

## Terminal emulator

[Alacritty](https://alacritty.org/) is the primary terminal;
[WezTerm](https://wezfurlong.org/wezterm/) is retained as a backup.

On Windows hosts both run on the Windows side and launch WSL via `wsl.exe`.
On native Linux both run on the same host as the shell and inherit the login
shell — the `wsl.exe` lines in the committed configs are simply not exercised.

### Alacritty (primary)

Config lives at `config/alacritty/alacritty.toml` (TOML): Campbell colors
(inlined), JetBrainsMono Nerd Font at 14pt, 120×28 initial window, 2px
padding, `Ctrl+Click` URL hints.

`install.sh link` symlinks it to `~/.config/alacritty/`. On Windows hosts the
Windows build reads `%APPDATA%\alacritty\alacritty.toml` instead — soft-link
that to the repo file for a single source of truth:

```powershell
winget install Alacritty.Alacritty
mkdir "$env:APPDATA\alacritty" -Force
New-Item -ItemType SymbolicLink `
  -Path "$env:APPDATA\alacritty\alacritty.toml" `
  -Target "\\wsl.localhost\Ubuntu-22.04\home\<user>\dotfiles\config\alacritty\alacritty.toml"
```

Notes:

- Windows hosts: default shell is `wsl.exe ~ -d Ubuntu-22.04` (no launch_menu
  — Alacritty has no GUI launcher). Native Linux: inherits the login shell.
- `TERM` is set to `alacritty` (terminfo via Linuxbrew ncurses 6.6); tmux's
  `alacritty:Tc` override handles TrueColor.
- OSC52 clipboard works natively — `"+y` in nvim reaches the Windows
  clipboard through tmux `set-clipboard external`, with zero config.
- No tab support by design — use tmux. `Ctrl+Click` opens URLs in the Windows
  default browser via `cmd.exe /c start`.

### WezTerm (backup)

Config at `config/wezterm/wezterm.lua`. On Windows hosts the default program
is PowerShell with a WSL entry in the launch menu; on native Linux it
inherits the login shell.

## tmux configuration

Everything runs inside [tmux](https://github.com/tmux/tmux): typically a
large top pane for Neovim and bottom or side panes for commands. No
pre-configured layouts — they are created on-the-fly as needed.

The status bar is styled and shows the system name, session name, and
current time. The prefix is `M-s` (Alt+s), not the default `⌃-b`.

### tmux key commands

Pane navigation and resizing use `M-h/j/k/l` and `M-H/J/K/L` (Alt + key,
**no prefix**), wired via [tmux.nvim](https://github.com/aserowy/tmux.nvim)
for seamless neovim↔tmux pane switching.

Prefix (`M-s`) + key:

| Command     | Description                    |
| ----------- | ------------------------------ |
| `h`         | Split pane to the left         |
| `j`         | Split pane to the bottom       |
| `k`         | Split pane to the top          |
| `l`         | Split pane to the right        |
| `c`         | Create a new window            |
| `r`         | Reload tmux config             |
| `b`         | Break pane into a new window   |
| `>` / `<`   | Swap pane down / up            |
| `←` / `→`   | Swap window left / right       |
| `'`         | Last window                    |
| `1`-`9`     | Select pane by index           |

Without prefix:

| Command     | Description                    |
| ----------- | ------------------------------ |
| `M-1`-`M-9` | Select window 1-9             |
| `M-w`       | Kill window                    |
| `M-q`       | Kill pane                      |
| `M-h/j/k/l` | Navigate pane left/down/up/right |
| `M-H/J/K/L` | Resize pane                    |

### SSH auto-attach

On SSH login, zsh auto-attaches the most-recently-used tmux session, with a
new-session fallback when the server is dead. Guards: skips inside tmux,
non-SSH shells, and non-TTY; opt out with `TMUX_NO_AUTO_ATTACH=1`.

Closing a terminal tab kills the ssh client but not the server-side session —
the next login lands straight back in it. `M-s d` detaches into the login
shell without dropping the SSH connection.

## Atuin (shell history)

[Atuin](https://github.com/atuinsh/atuin) replaces shell history with a
searchable, syncable SQLite database. This setup runs **local-only** (no
cloud account); search uses fzf-style fuzzy matching to match the existing
fzf workflow.

### Installation

Atuin is listed in the [Brewfile](./Brewfile) and installed by
`./install.sh homebrew`. The config is symlinked to
`~/.config/atuin/config.toml` by `./install.sh link`.

The zsh integration (`zsh/atuin.zsh`) is auto-sourced by `zshrc.symlink`.

### Keybindings

| Key | Action |
| --- | --- |
| `Ctrl-R` | Open Atuin fuzzy search UI (replaces fzf history search) |
| `Up` | Cycle history filtered to the current directory |
| `Ctrl-R` (inside UI) | Cycle filter modes: global → host → session → directory → workspace |
| `Tab` | Copy selected command to the command line for editing |
| `Enter` | Execute the selected command immediately (`enter_accept = true`) |
| `Esc` | Restore the original command line |
| `Ctrl-A` then `D` | Delete the selected history entry (prefix mode) |
| `Ctrl-T` / `Alt-C` | Still fzf file / directory search (unaffected by Atuin) |

Prefix a command with a space to keep it out of history (ignorespace).

### Common CLI

```bash
atuin search <query>      # search history from the command line
atuin history list        # list recorded history
atuin stats               # show shell usage statistics
atuin doctor              # diagnose shell integration
atuin import auto         # import existing shell history (run once)
atuin history prune       # remove entries matching history_filter / cwd_filter
```

### Enabling cloud sync later (optional)

This setup is local-only. To enable cross-machine encrypted sync later:

1. Add to `~/.config/atuin/config.toml`:
   ```toml
   auto_sync = true
   [sync]
   records = true
   ```
2. `atuin register -u <username> -e <email>`
3. Save the encryption key printed by `atuin key` to a safe location.
4. `atuin sync`

See the [Atuin docs](https://docs.atuin.sh/) for full reference.

## Yazi (file manager)

[Yazi](https://github.com/sxyazi/yazi) is a fast terminal file manager with
async I/O and image preview. It complements `fzf` — use **fzf for known
targets** (`Ctrl-T` / `Alt-C`) and **yazi for browsing** and image previews.

### Installation

Yazi and `chafa` (image-preview fallback for tmux, especially on WSL2 where
no native GPU preview is available) are listed in the [Brewfile](./Brewfile)
and installed by `./install.sh homebrew`.

The config is symlinked to `~/.config/yazi/` by `./install.sh link`, and the
shell integration (`zsh/yazi.zsh`) is auto-sourced by `zshrc.symlink`.

### Shell commands

| Command | Action |
| --- | --- |
| `y` | Launch yazi in the current directory |
| `yc` | Launch yazi and **cd to the directory it was in on quit** (replaces the former nnn `cdn`) |

### Keybindings (yazi defaults + one override)

| Key | Action |
| --- | --- |
| `h` / `l` | Go to parent / enter child directory |
| `j` / `k` | Move down / up |
| `Enter` / `o` | Open selected file (text → `$EDITOR` = nvim, images → `xdg-open`) |
| `z` | Jump to a file/directory via fzf |
| `Z` | Jump to a directory via zoxide |
| `s` / `S` | Search by name (fd) / by content (ripgrep) |
| `Space` | Toggle selection |
| `cc` / `cd` / `cf` | Copy path / dirname / filename |
| `,g` | **Spawn lazygit in CWD** (custom override in `keymap.toml`) |
| `q` | Quit (writes CWD for `yc`) |

### Configuration

Only values that diverge from yazi's shipped defaults are committed:

- `config/yazi/yazi.toml` — `show_hidden = true`, `linemode = "size"`,
  `sort_by = "mtime"` (newest first).
- `config/yazi/keymap.toml` — `prepend_keymap` adds `,g` → `lazygit`; all
  defaults preserved.

No `theme.toml` is shipped (yazi's built-in dark theme matches the terminal).

### Practical usage

1. **`yc`** — open yazi, browse with `hjkl`, `q` to exit back into the cwd
   you left. The single most useful thing: yazi as a "where did I put that
   file" tool that leaves you positioned correctly when you quit.
2. **Image previews** — yazi's killer feature. On tmux (WSL2 or native
   Linux) + Alacritty (or wezterm), the `chafa` fallback renders images as
   ANSI block art. Scan a folder of screenshots without leaving the terminal.
3. **Code previews** — press `K` / `J` to scroll the preview pane; yazi
   renders files with syntax highlighting and the directory tree on the
   right.
4. **Open in nvim from yazi** — `Enter` / `o` opens the highlighted file in
   nvim (text files only; images open via `xdg-open`).
5. **`,g` from inside yazi** — spawns lazygit in the current pane's dir,
   without leaving yazi.
6. **Use alongside fzf** — `Ctrl-T` (fzf file) and `Alt-C` (fzf dir) stay as
   the "I know the name" path; yazi is the "I need to look around" path.

**Rule of thumb:** fzf for *known targets*, yazi for *browsing* and *images*.

## OpenCode (AI coding agent)

[OpenCode](https://opencode.ai) is an open-source AI coding agent CLI/TUI.
This repo manages its **personal/portable** global config so MCP servers,
custom commands, and global rules are version-controlled and portable.

Work-specific providers and MCP live in a machine-local overlay — see
[Work overlay](#work-overlay-machine-local-not-in-repo) below.

### Installation

OpenCode is installed via `./install.sh homebrew` (see
[Brewfile](./Brewfile)). The config is symlinked to `~/.config/opencode/` by
`./install.sh link` — the same `config/<tool>` convention as
atuin/yazi/alacritty.

### Managed files

| File | Purpose |
| --- | --- |
| `config/opencode/opencode.json` | **Personal base only**: MCP servers (`context7` remote, `codegraph` local), `lsp: true`, `permission` gates, formatters (`clang-format`), plugins (`@franlol/opencode-md-table-formatter`). No providers, no secrets. |
| `config/opencode/commands/commit.md` | The `/commit` custom command — a Conventional Commits message generator that reads the staged diff, recent history, and `AGENTS.md` |
| `config/opencode/AGENTS.md` | Global rules (web-fetching strategy + MCP priority) — symlinked to `~/.config/opencode/AGENTS.md`, applied to every opencode session |
| `config/opencode/commands/pr.md` | The `/pr` custom command — full GitHub Flow (branch, commit, push, `gh pr create`) |

### Work overlay (machine-local, not in repo)

Work-specific config — company model providers and the `jira` MCP — is kept
out of this personal repo.

opencode deep-merges config sources in order: global
(`~/.config/opencode/opencode.json`) → `OPENCODE_CONFIG` env-var file →
project-level.

The work overlay lives at `~/.config/opencode-work.json` — a real file in
`~/.config/`, **not** inside the symlinked `~/.config/opencode/` dir, so it
never touches the repo worktree.

On work machines, `~/.zshrc.local` sets
`export OPENCODE_CONFIG="$HOME/.config/opencode-work.json"`; personal
machines leave it unset, so only the personal base loads.

**No secrets live in the repo or the overlay.** Provider credentials are
stored in `~/.local/share/opencode/auth.json` (never committed) and loaded
by the opencode CLI at startup.

The overlay uses `{env:...}` references (e.g. `JIRA_PERSONAL_TOKEN`) for any
secret-bearing values.

Avante.nvim talks to opencode via ACP (Agent Client Protocol), so it reuses
the same merged providers — no separate env-var wiring or duplicated
provider config.

### Runtime files (gitignored)

OpenCode regenerates several files inside the symlinked
`~/.config/opencode/` dir at runtime; these are gitignored at repo root and
must not be committed:

- `node_modules/`, `package.json`, `package-lock.json`, `bun.lock` — plugin
  install state (regenerated from `opencode.json`'s `plugin` array)
- `antigravity-accounts.json*`, `antigravity-signature-cache.json`,
  `antigravity-logs/` — antigravity provider session state
- `plugins/` — work-only plugins (e.g. `git-ai.ts`), machine-generated by
  `git-ai install-hooks` with a hardcoded binary path

### Shell commands

| Command | Action |
| --- | --- |
| `occm` | Generate a conventional commit message via `opencode run --command commit` (pass `-m <provider/model>` to select a model; extra args become instructions) |
| `ocpr` | Run the `/pr` custom command headlessly via `opencode run --command pr` |
| `opencode` | Launch the TUI |

### Adding a custom command

Drop a markdown file in `config/opencode/commands/<name>.md` with frontmatter
(`description`, optional `agent`/`model`) and a prompt template.

It becomes `/name` in the TUI and `opencode run --command name` on the CLI.
See [the commands docs](https://opencode.ai/docs/commands) and the existing
`commit.md` for a reference template.

## Uninstall

`uninstall.sh` reverses `install.sh` — removes the symlinks (each verified to
point into the repo), repo-managed artifacts (oh-my-zsh, TPM plugins), and
machine-local files (`~/.gitconfig-local`, `~/.fzf.zsh`, `~/.codegraph/`).

Shell restore is tiered like the install: local users get
`chsh -s /bin/bash`; AD/SSSD users get `sss_override user-del` (removes the
override, restoring the AD-defined shell — which may or may not be
`/bin/bash`).

The `~/.bashrc` zsh exec fallback block is always removed if present.

```bash
./uninstall.sh           # config + machine-local + shell
./uninstall.sh --data    # also remove nvim/atuin/opencode runtime data (prompts)
```

Homebrew itself is **not** uninstalled (multi-user safety) — the script
prints the manual command if needed. The dotfiles repo is also left in place.

## Docker testing

The `Dockerfile` builds an Ubuntu image as a testing ground for the Linux
install path (SSH keys injected via build args):

```bash
docker build -t dotfiles --force-rm \
  --build-arg PRIVATE_KEY="$(cat ~/.ssh/id_rsa)" \
  --build-arg PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)" .
```

Run it and manually test the installation process inside:

```bash
docker run -it --rm dotfiles
```

## Preferred software

- [Alacritty](https://alacritty.org/) — GPU-accelerated terminal (primary);
  cross-platform, TOML config, native OSC52 clipboard
- [WezTerm](https://wezfurlong.org/wezterm/) — GPU-accelerated terminal
  (backup); good tmux and WSL2 support
- [tmux](https://github.com/tmux/tmux) — terminal multiplexer
- [Neovim](https://neovim.io/) — hyper-extensible Vim-based text editor
- [fzf](https://github.com/junegunn/fzf) — fuzzy finder for known targets
- [Atuin](https://github.com/atuinsh/atuin) — searchable shell history
- [Yazi](https://github.com/sxyazi/yazi) — terminal file manager with image
  preview
- [OpenCode](https://opencode.ai) — open-source AI coding agent CLI/TUI

## Questions

If you have questions, notice issues, or would like to see improvements,
please open a new [discussion](https://github.com/qq123538/dotfiles/discussions/new)
and I'm happy to help you out!
