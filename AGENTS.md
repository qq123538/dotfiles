# AGENTS.md

Guidance for OpenCode agents in this dotfiles repo. Trust `install.sh` and the
actual config files over `README.md` prose — several README sections were stale
and have been fixed, but always verify against the source.

## Repo shape
- Personal dotfiles (forked from nicknisi/dotfiles). No build/test/lint/CI,
  no package manifest. Verification is manual: run `install.sh`, open zsh/nvim/tmux.
- Default branch `main` (protected — never push directly). Workflow is GitHub
  Flow: create a feature branch
  (`{feat|fix|docs|refactor|chore|perf|test|build|ci|revert|style}/<scope>`), push
  it, open a PR with `gh pr create`. Merges on GitHub squash into one commit
  titled `<PR title> (#N)`.
- Conventional Commits is required for **both PR titles and commit messages**
  — squash makes the PR title the permanent main-history entry. Format:
  `type(scope): <lowercase imperative subject, ≤72 chars>`.
  - type: `feat fix docs style refactor perf test build ci chore revert`.
    Breaking change: `type(scope)!:` or `BREAKING CHANGE:` footer.
  - scope: tool/module name (`zsh nvim tmux git alacritty wezterm brew install
    agents yazi ai codegraph`); multiple scopes comma-separated, e.g. `feat(zsh,config):`.
  - body: `feat/fix/refactor/perf` recommended — write "why" not "what" (the
    diff shows what), use `-` bullets, ≤72 chars/line, blank line after subject.
    `chore/style/revert` and simple single-file changes may omit.
    `BREAKING CHANGE:`/`Co-authored-by:` go in the footer.
  - squash merge copies the PR description into the commit body — a good PR
    description is a readable main history.
- Target environment: Linux workstation (Ubuntu 22.04; native bare-metal or
  WSL2). Corporate machines use AD/SSSD directory-service users (not in
  `/etc/passwd`) — see "Query the working environment first" below.
  Terminals: Alacritty (primary) / WezTerm (backup) + tmux + Neovim. On
  Windows hosts the terminals launch WSL via `wsl.exe`; on native Linux
  they inherit the login shell set by `install.sh shell`.

## Query the working environment first
**Do not assume WSL2, or any specific host/user model.** Before recommending
shell-switch commands, sudo-dependent steps, or terminal-launch paths, probe
the live host. The installer's `is_directory_service_user` uses the same
probes, so the AI's mental model must match the installer's.

```bash
# AD/SSSD user vs local /etc/passwd user (matches is_directory_service_user)
getent -s files passwd "$USER"   # local user if this returns a row
getent passwd "$USER"            # directory-service if only this returns a row

# WSL vs native Linux
[ -e /run/WSL ] || [ -e /proc/sys/fs/binfmt_misc/WSLInterop ]   # WSL if true
cat /proc/sys/kernel/osrelease    # Microsoft kernel string also signals WSL
cat /etc/os-release               # distro/version

# Tools the installer depends on
command -v brew; command -v sss_override; command -v chsh
sudo -n true 2>/dev/null && echo "passwordless sudo" || echo "sudo needs password / unavailable"

# Current login shell (what install.sh shell would try to change)
getent passwd "$USER" | cut -d: -f7
```

Decision rules derived from the probes:
- **Local user** (`getent -s files` returns a row) → `install.sh shell` uses
  `chsh -s <brew zsh>`. Standard path.
- **AD/SSSD user** (`getent -s files` empty, `getent` returns a row) +
  `sss_override` present + passwordless sudo → `install.sh shell` uses
  `sss_override user-add` (first creation restarts `sssd`, subsequent updates
  use `sss_cache -u`). This is the corporate-workstation path.
- **AD/SSSD user without sudo** (or `sss_override` absent) → `install.sh shell`
  falls back to a sentinel-guarded `~/.bashrc` exec block (interactive
  terminals only). **Non-interactive sessions (cron, `ssh -c`, `su -`) stay
  bash** — `$SHELL` is not changed. For a real change the user must ask their
  AD admin to set `loginShell`.
- **WSL** → Windows-side terminals (`alacritty.toml`, `wezterm.lua`) launch
  `wsl.exe`; the WSLg Alacritty path applies. **Native Linux** → those configs
  do not apply (Alacritty/WezTerm run on the same host and inherit the login
  shell); do not instruct the user to run the PowerShell soft-link recipe.

## Symlink install model (core mechanism)
`install.sh link` symlinks config into `$HOME`:
- `**/*.symlink` -> `~/.<basename>` (`.symlink` stripped). E.g. `zsh/zshrc.symlink`
  -> `~/.zshrc`, `zsh/p10k.zsh.symlink` -> `~/.p10k.zsh`.
- Each top-level entry in `config/` -> `~/.config/<entry>`. E.g. `config/nvim`
  -> `~/.config/nvim`; `config/git/config` is the XDG global gitconfig at
  `~/.config/git/config` (git reads it via XDG, not `~/.gitconfig`).

Editing these files edits the live linked config. To add a new tool config, drop
it under `config/<tool>/` and re-run `./install.sh link`.

## install.sh subcommands
`{backup|link|git|homebrew|ohmyzsh|shell|codegraph|all}`.
- `all` runs `link`, `homebrew`, `git`, `ohmyzsh`, `shell`, `codegraph`. It
  does **not** run `backup` — run that manually if needed.
- The brew subcommand is `homebrew` (not `brew`). It runs `brew bundle` against
  `Brewfile`, then installs fzf keybindings. `brew bundle` failures now abort
  `setup_homebrew` (previously passed through silently on non-zero exit).
- `git` writes `~/.gitconfig-local` (machine-specific, not in repo).
- **Fresh-machine prerequisite**: `homebrew` (and thus `all`) needs `sudo` to
  create `/home/linuxbrew/.linuxbrew` when brew isn't yet installed. The
  installer downloads-then-runs (not piped) so it keeps a TTY and can prompt
  for the password. `git` + `curl` must be pre-installed.
- **Multi-user behavior** (`setup_homebrew` three states): (1) brew absent →
  installs via official script (needs sudo); (2) brew present + prefix
  writable by `$USER` → runs `brew bundle` (owner); (3) brew present + prefix
  not writable → skips `brew bundle`, warns, returns 0 (read-only reuse of
  another user's binaries via PATH). This is Homebrew's supported multi-user
  model — one owner installs, others consume.
- **Tiered `setup_shell`** (probes `is_directory_service_user` first):
  (1) local user in `/etc/passwd` → `chsh -s <brew zsh>` (standard path);
  (2) AD/SSSD user + `sss_override` present + passwordless sudo →
  `sss_override user-add` — first creation for the user restarts `sssd` (per
  `sss_override(8)`, the first override needs an sssd restart to take effect),
  subsequent updates use `sss_cache -u <user>` (per-user, less disruptive);
  (3) AD/SSSD user without sudo (or `sss_override` absent) → falls back to a
  sentinel-guarded `~/.bashrc` exec block (`# >>> dotfiles managed (AD user
  shell fallback) >>>` … `# <<< ... <<<`) that `exec`s zsh on interactive
  login. **Non-interactive sessions (cron, `ssh -c`, `su -`) stay bash** in
  this fallback case — `$SHELL` is not changed; for a real change the user
  must ask their AD admin to set `loginShell`. `/etc/shells` is still probed
  first (required by both `chsh` and SSSD shell validation).
- **`setup_ohmyzsh`** detects incomplete installs by checking for
  `$ZSH/oh-my-zsh.sh` (not just dir existence). A previously-failed `curl`
  leaving an empty `$ZSH` dir would otherwise be skipped forever; oh-my-zsh's
  own installer also aborts on non-empty targets, so incomplete dirs are
  `rm -rf`'d before re-attempting.
- **`uninstall.sh`** reverses `install.sh`: removes symlinks (verifying each
  points into `$DOTFILES` via readlink), repo artifacts (`$DOTFILES/zsh/.oh-my-zsh`,
  `$DOTFILES/config/tmux/plugins`), machine-local files (`~/.gitconfig-local`,
  `~/.git-credentials`, `~/.gitconfig` credential.helper, `~/.fzf.zsh`,
  `~/.codegraph/`), and **always removes the `~/.bashrc` fallback block** if
  present. Shell restore is tiered: AD/SSSD users get `sss_override user-del`
  (restores AD-defined shell, which may or may not be `/bin/bash` — not
  forced, that's an AD-admin concern); local users get `chsh -s /bin/bash`.
  `--data` also removes nvim/atuin/opencode runtime data with a `yes`
  confirmation gate. Does NOT uninstall Homebrew (multi-user safety) or
  delete the repo. `/etc/shells` left untouched (other users may need it).

## zsh wiring
- `$DOTFILES` (set in `zsh/zshenv.symlink` via readlink resolution) = repo root.
  Many configs depend on it.
- `zshrc.symlink` sources every `$DOTFILES/**/*.zsh` — a new `*.zsh` file
  auto-loads. `zsh/functions/` is on `fpath` (autoloadable: `occm`, `ocpr`).
- Shell is oh-my-zsh + powerlevel10k (installed to `$DOTFILES/zsh/.oh-my-zsh`,
  gitignored).
- Machine-local overrides (sourced if present, not in repo): `~/.localrc`,
  `~/.zshrc.local`, `~/.zshenv.local`, `~/.gitconfig-local`.

## Neovim (AstroNvim v6)
- Entry `config/nvim/init.lua` bootstraps lazy.nvim -> `lua/lazy_setup.lua` ->
  imports `community` (`lua/community.lua`, astrocommunity packs) +
  `lua/plugins/*.lua` (user plugin specs).
- Plugins auto-install on first `nvim` launch. `lazy-lock.json` is gitignored
  (not a committed lockfile). Headless sync: `nvim --headless "+Lazy! sync" +qa`
  or `:Lazy` inside Neovim.
- Lua formatting = StyLua per `config/nvim/.stylua.toml` (4-space, 120 col,
  `call_parentheses = None`). Do NOT use the root `.lua-format` (2-space,
  different tool) for nvim Lua.
- Leader `<Space>`, localleader `,`.
- Neovim 0.11+ has built-in OSC52 clipboard support — `"+y` reaches the Windows
  clipboard via tmux `set-clipboard external` -> Wezterm OSC52, with zero config.

## AI: avante.nvim via opencode ACP
`config/nvim/lua/plugins/ai.lua` sets avante.nvim's `provider = "opencode"`,
using avante's built-in ACP (Agent Client Protocol) provider. Avante spawns
`opencode acp`; the opencode CLI reads `~/.config/opencode/opencode.json` and
serves all providers/models/MCP/permissions from there. No provider config is
duplicated in `ai.lua` — add/change models in `opencode.json` instead. Switch
agent at runtime with `:AvanteSwitchProvider`; `<leader>aM` selects ACP model,
`<leader>am` selects ACP mode.

## OpenCode (opencode CLI config)
`config/opencode/` -> `~/.config/opencode/` via `install.sh link` (same
`config/<tool>` convention as atuin/yazi/alacritty). This repo tracks only the
**personal/portable** base; work-specific providers and MCP live in a machine-local
overlay (see "Work overlay" below). Managed files:
- `opencode.json` — **personal base only**: MCP servers (`context7` remote,
  `codegraph` local), `lsp: true` (diagnostic feedback), `permission` (safety
  gates: `rm`/force-push ask, rest allow), formatters (`clang-format`), plugins
  (`@franlol/opencode-md-table-formatter`). **No providers, no secrets here.**
  Provider credentials live in `~/.local/share/opencode/auth.json` (never in repo).
- `AGENTS.md` — **global rules**, symlinked to
  `~/.config/opencode/AGENTS.md`, applied to every opencode session. Holds the
  web-fetching fallback strategy (context7 / Jina Reader / gh) and MCP usage
  priority rules (context7 for lib docs, codegraph for code structure). A
  project's own `AGENTS.md` layers on top and takes precedence.
- `commands/commit.md` — the `/commit` custom command (Conventional Commits
  message generator, reads staged diff + recent history + AGENTS.md).
- `commands/pr.md` — the `/pr` custom command (full GitHub Flow: branch,
  commit, push, `gh pr create`).

### Work overlay (machine-local, not in repo)
Work-specific config — company model providers (e.g. NIO ModelSight / Token-X)
and the `jira` MCP — is kept out of this personal repo. opencode deep-merges
config sources in order: global (`~/.config/opencode/opencode.json`) →
`OPENCODE_CONFIG` env-var file → project-level. The work overlay lives at
`~/.config/opencode-work.json` (a real file in `~/.config/`, **not** inside the
symlinked `~/.config/opencode/` dir, so it never touches the repo worktree).
On work machines, `~/.zshrc.local` sets `export OPENCODE_CONFIG="$HOME/.config/opencode-work.json"`;
personal machines leave it unset, so only the personal base loads. No secrets in
the overlay either — `JIRA_PERSONAL_TOKEN` is `{env:...}` and provider creds
are in `~/.local/share/opencode/auth.json`.

Built-in `websearch` (Exa, free, no API key) is enabled globally via
`OPENCODE_ENABLE_EXA=1` in `zsh/zshenv.symlink` — required when not on the
opencode provider. LSP is on (`lsp: true`); lua-ls and clangd auto-install,
Python needs a manual `npm install -g pyright`. Disable a single server
per-project with `lsp.<name>.disabled: true`.

Runtime files opencode regenerates inside the symlinked dir are gitignored at
repo root: `node_modules/`, `package.json`, `package-lock.json`, `bun.lock`,
`antigravity-accounts.json*`, `antigravity-signature-cache.json`,
`antigravity-logs/`, and `plugins/` (work-only plugins like `git-ai.ts`, which
is machine-generated by `git-ai install-hooks` with a hardcoded binary path).
The `oh-my-opencode` plugin was uninstalled (its config file is not managed);
`package.json` is regenerated from `opencode.json`'s `plugin` array on next
launch.

`occm` (`zsh/functions/occm`) is a shell function that runs
`opencode run --command commit "$@"` — i.e. it invokes the `/commit` command
defined in `config/opencode/commands/commit.md` headlessly. To add a new
custom command, drop `config/opencode/commands/<name>.md` (frontmatter +
template, per https://opencode.ai/docs/commands).

## CodeGraph (global code-knowledge MCP)
CodeGraph is a pre-indexed, 100% local knowledge graph of symbols/calls/deps
for AI coding agents (opencode, Claude Code, Cursor, etc.). Exposes one MCP
tool — `codegraph_explore` — that returns surgical context + call paths in a
single call instead of a grep/Read crawl. 20+ languages, auto-syncs on file
changes. Repo: https://github.com/colbymchenry/codegraph
- **CLI install**: `./install.sh codegraph` (idempotent). Not on Homebrew; the
  official installer bundles its own Node runtime and places `codegraph` on a
  user bin already on PATH (`~/.local/bin` via `zsh/zshenv.symlink`). Also run
  by `./install.sh all`. No Node dependency on the brew-managed `node`.
- **opencode MCP wiring**: `config/opencode/opencode.json` has a `codegraph`
  local MCP server (`["codegraph", "serve", "--mcp"]`, `enabled: true`).
  Configured manually — **do not** run `codegraph install` (it would rewrite
  agent configs and AGENTS.md out of band).
- **Per-project indexing is manual and NOT in this repo**: run `codegraph init`
  in each *code* project to build its `.codegraph/` graph. This dotfiles repo
  only does the *global* wiring (CLI + MCP config). Projects without a
  `.codegraph/` index degrade gracefully — CodeGraph tells the agent to use
  built-in tools.
- `.codegraph/` is gitignored at repo root as a safety net.
- Scope is **opencode only** here — this repo does not manage `~/.claude.json`
  or other agents' configs, so CodeGraph's Claude Code/Cursor wiring is out of
  scope for this dotfiles.

## tmux
- Prefix is `M-s` (Alt+s). `prefix + I` installs TPM plugins.
- TrueColor override: `terminal-overrides ",xterm-256color:Tc,wezterm:Tc,alacritty:Tc"` —
  covers the TERM values each terminal may set.
- TPM init `run '$HOMEBREW_PREFIX/opt/tpm/share/tpm/tpm'` requires
  `$HOMEBREW_PREFIX` (set by `zprofile.symlink` on macOS/Linuxbrew).
- tmux-resurrect restores `~gemini copilot opencode`. Plugins live in
  `config/tmux/plugins/` (gitignored).
- Pane navigation: `M-h/j/k/l` (no prefix) via tmux.nvim, seamless with neovim.

## Alacritty (primary terminal)
- Config at `config/alacritty/alacritty.toml` -> `~/.config/alacritty/` via
  `install.sh link` (the Linux build's native path). On **Windows hosts** the
  Windows build reads `%APPDATA%\alacritty\alacritty.toml`; soft-link that
  to the repo file via
  `\\wsl.localhost\<distro>\home\<user>\dotfiles\config\alacritty\alacritty.toml`
  so the repo stays the single source of truth. On **native Linux hosts**
  Alacritty runs on the same host as the shell and inherits the login shell
  set by `install.sh shell` — the `wsl.exe` line in the committed config is
  a Windows-deployment concern and is simply not exercised on native Linux.
- Default shell launches `wsl.exe ~ -d Ubuntu-22.04` directly (no launch_menu
  like WezTerm) — applies on Windows hosts only.
- `TERM=alacritty` is set in `[env]` (the alacritty terminfo is available
  via Linuxbrew ncurses 6.6); tmux's `alacritty:Tc` override handles TrueColor.
- OSC52 clipboard works natively — `"+y` in nvim reaches the Windows clipboard through
  tmux `set-clipboard external`. Zero config, same path as WezTerm.
- No tab support by design — use tmux. URL hints: `Ctrl+Click` opens in Windows default
  browser via `cmd.exe /c start`.
- WezTerm config (`config/wezterm/wezterm.lua`) retained as backup terminal.

## git config
- `config/git/config` -> `~/.config/git/config` (XDG global gitconfig, read
  via XDG — not `~/.gitconfig`). `pull.rebase = true`,
  `push.default = current`, pager is `delta`, `core.editor` is `vim`
  (not `nvim`). Credential helper is per-OS via `~/.gitconfig-local`
  (written by `install.sh git` — no hardcoded helper in the committed config).
- Identity pinning: `config/git/config` has an
  `[includeIf "hasconfig:remote.*.url:*qq123538/dotfiles*"]` block that
  pulls in `config/git/identity-personal` (personal `[user]`, GitHub noreply
  email) for this repo only — matches by remote URL so it survives any clone
  path. Prerequisite (machine-local, one-time per machine): classic
  `~/.gitconfig` must NOT set `[user]` (it outranks XDG and would override
  the includeIf). With it removed, the work identity comes only from
  `~/.gitconfig-local` (included above), and this repo overrides to personal;
  other repos keep the work default. No secrets — noreply email is already
  public via every commit in this repo's history.

## Linux testing
`Dockerfile` builds an Ubuntu image injecting SSH keys via
`--build-arg PRIVATE_KEY/PUBLIC_KEY` to test the linux install path:
`docker build -t dotfiles --build-arg PRIVATE_KEY="$(cat ~/.ssh/id_rsa)" \
  --build-arg PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)" .` then `docker run -it --rm dotfiles`.
