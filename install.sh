#!/usr/bin/env bash

DOTFILES="$(pwd)"
COLOR_GRAY="\033[1;38;5;243m"
COLOR_BLUE="\033[1;34m"
COLOR_GREEN="\033[1;32m"
COLOR_RED="\033[1;31m"
COLOR_PURPLE="\033[1;35m"
COLOR_YELLOW="\033[1;33m"
COLOR_NONE="\033[0m"

title() {
    echo -e "\n${COLOR_PURPLE}$1${COLOR_NONE}"
    echo -e "${COLOR_GRAY}==============================${COLOR_NONE}\n"
}

error() {
    echo -e "${COLOR_RED}Error: ${COLOR_NONE}$1"
    exit 1
}

warning() {
    echo -e "${COLOR_YELLOW}Warning: ${COLOR_NONE}$1"
}

info() {
    echo -e "${COLOR_BLUE}Info: ${COLOR_NONE}$1"
}

success() {
    echo -e "${COLOR_GREEN}$1${COLOR_NONE}"
}

get_linkables() {
    find -H "$DOTFILES" -maxdepth 3 -name '*.symlink'
}

backup() {
    BACKUP_DIR=$HOME/dotfiles-backup

    echo "Creating backup directory at $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"

    for file in $(get_linkables); do
        filename=".$(basename "$file" '.symlink')"
        target="$HOME/$filename"
        if [ -f "$target" ]; then
            echo "backing up $filename"
            cp "$target" "$BACKUP_DIR"
        else
            warning "$filename does not exist at this location or is a symlink"
        fi
    done

    for filename in "$HOME/.config/nvim" "$HOME/.vim" "$HOME/.vimrc"; do
        if [ ! -L "$filename" ]; then
            echo "backing up $filename"
            cp -rf "$filename" "$BACKUP_DIR"
        else
            warning "$filename does not exist at this location or is a symlink"
        fi
    done
}


setup_symlinks() {
    title "Creating symlinks"

    for file in $(get_linkables) ; do
        target="$HOME/.$(basename "$file" '.symlink')"
        if [ -e "$target" ]; then
            info "~${target#$HOME} already exists... Skipping."
        else
            info "Creating symlink for $file"
            ln -s "$file" "$target"
        fi
    done

    echo -e
    info "installing to ~/.config"
    if [ ! -d "$HOME/.config" ]; then
        info "Creating ~/.config"
        mkdir -p "$HOME/.config"
    fi

    config_files=$(find "$DOTFILES/config" -mindepth 1 -maxdepth 1 2>/dev/null)
    for config in $config_files; do
        target="$HOME/.config/$(basename "$config")"
        if [ -e "$target" ]; then
            info "~${target#$HOME} already exists... Skipping."
        else
            info "Creating symlink for $config"
            ln -s "$config" "$target"
        fi
    done
}

setup_git() {
    title "Setting up Git"

    defaultName=$(git config user.name)
    defaultEmail=$(git config user.email)
    defaultGithub=$(git config github.user)

    read -rp "Name [$defaultName] " name
    read -rp "Email [$defaultEmail] " email
    read -rp "Github username [$defaultGithub] " github

    git config -f ~/.gitconfig-local user.name "${name:-$defaultName}"
    git config -f ~/.gitconfig-local user.email "${email:-$defaultEmail}"
    git config -f ~/.gitconfig-local github.user "${github:-$defaultGithub}"

    read -rn 1 -p "Save user and password to an unencrypted file to avoid writing? [y/N] " save
    if [[ $save =~ ^([Yy])$ ]]; then
        git config --global credential.helper "store"
    else
        git config --global credential.helper "cache --timeout 3600"
    fi
}

setup_homebrew() {
    title "Setting up Homebrew"

    # Put any existing brew on PATH before deciding what to do. shellenv only
    # reads the prefix, so this is safe for non-owner users too.
    if [ "$(uname)" == "Linux" ]; then
        test -d ~/.linuxbrew && eval "$(~/.linuxbrew/bin/brew shellenv)"
        test -d /home/linuxbrew/.linuxbrew && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi

    if test ! "$(command -v brew)"; then
        # brew absent (fresh machine). Download-then-run instead of piping so
        # bash keeps a TTY stdin: the Homebrew installer then stays interactive
        # and can prompt for the sudo password it needs to create the supported
        # /home/linuxbrew/.linuxbrew prefix. Piping (curl | bash) forces
        # NONINTERACTIVE=1 -> sudo -n -> "a password is required" abort even
        # for users who do have sudo.
        info "Homebrew not installed. Installing."
        local brew_installer="/tmp/brew-install-$$.sh"
        if ! curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh -o "$brew_installer"; then
            rm -f "$brew_installer"
            error "Failed to download Homebrew installer."
        fi
        bash --login "$brew_installer"; local rc=$?
        rm -f "$brew_installer"
        [ $rc -ne 0 ] && error "Homebrew installation failed (exit $rc)."
        if [ "$(uname)" == "Linux" ]; then
            test -d ~/.linuxbrew && eval "$(~/.linuxbrew/bin/brew shellenv)"
            test -d /home/linuxbrew/.linuxbrew && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
        fi
    fi

    local prefix
    prefix="$(brew --prefix 2>/dev/null)"
    if [ ! -w "$prefix" ]; then
        # Homebrew exists but is owned by another user (e.g. test5 reusing an
        # install done by wl_ubuntu). Skip brew bundle / fzf install: those
        # write to the prefix (Cellar, locks, opt) and would fail with
        # "Permission denied @ rb_sysopen .../locks/...". Pre-installed
        # binaries stay usable via PATH. Homebrew is designed for single-user
        # ownership; this read-only reuse is the supported multi-user pattern.
        warning "Homebrew prefix ($prefix) is not writable by $USER; skipping 'brew bundle'."
        warning "Installed binaries remain usable on PATH. Ask the prefix owner to run './install.sh homebrew' to install or update packages."
        return 0
    fi

    # install brew dependencies from Brewfile
    if ! brew bundle; then
        error "brew bundle failed. See output above."
    fi

    # install fzf
    echo -e
    info "Installing fzf"
    "$(brew --prefix)"/opt/fzf/install --key-bindings --completion --no-update-rc --no-bash --no-fish
}

# Detect whether $USER is a directory-service user (AD/SSSD/LDAP) rather than
# a local /etc/passwd entry. `getent -s files` queries only /etc/passwd
# (bypasses SSSD), so a user resolvable via NSS but absent from /etc/passwd is
# a directory-service user — for whom `chsh` fails ("user does not exist in
# /etc/passwd"). Returns 0 = directory-service, 1 = local, 2 = not found.
is_directory_service_user() {
    if getent -s files passwd "$USER" >/dev/null 2>&1; then
        return 1
    fi
    if getent passwd "$USER" >/dev/null 2>&1; then
        return 0
    fi
    return 2
}

# Set login shell for an AD/SSSD user via SSSD's client-side view
# (sss_override user-add). Creates a per-user local override in the SSSD
# cache; does not touch AD or /etc/passwd. Requires sudo. Returns 0 on
# success, non-zero otherwise.
try_sss_override() {
    local zsh_path="$1"

    if ! command -v sss_override >/dev/null 2>&1; then
        warning "sss_override not found — cannot use SSSD override path."
        return 1
    fi
    if ! sudo -n true 2>/dev/null; then
        warning "sudo required for sss_override but not available passwordlessly."
        warning "Run: sudo sss_override user-add '$USER' -s '$zsh_path'"
        return 1
    fi

    # Detect first-time override creation. Per sss_override(8), the FIRST
    # override requires `systemctl restart sssd` to take effect (sss_override
    # itself prints "SSSD needs to be restarted"); subsequent updates only
    # need `sss_cache -u <user>` (per-user, less disruptive). user-show
    # exits non-zero when no override exists yet.
    local first_creation=0
    if ! sudo sss_override user-show "$USER" >/dev/null 2>&1; then
        first_creation=1
    fi

    info "Setting login shell via SSSD override (sss_override user-add)."
    if ! sudo sss_override user-add "$USER" -s "$zsh_path"; then
        warning "sss_override user-add failed."
        return 1
    fi

    if [[ "$first_creation" -eq 1 ]]; then
        info "First SSSD override for $USER — restarting sssd to take effect."
        if sudo systemctl restart sssd; then
            info "sssd restarted."
        else
            warning "Failed to restart sssd; new shell may not take effect until next SSSD restart."
        fi
    else
        if sudo sss_cache -u "$USER" 2>/dev/null; then
            info "SSSD cache refreshed for $USER."
        else
            warning "sss_cache failed; falling back to 'systemctl restart sssd'."
            sudo systemctl restart sssd || warning "Failed to restart sssd."
        fi
    fi

    local actual_shell
    actual_shell="$(getent passwd "$USER" | cut -d: -f7)"
    if [[ "$actual_shell" == "$zsh_path" ]]; then
        success "Login shell set to $zsh_path via SSSD override (takes effect on next login)."
        return 0
    else
        warning "sss_override ran but getent still reports shell='$actual_shell'."
        warning "Try: sudo systemctl restart sssd"
        return 1
    fi
}

# Append a sentinel-guarded block to ~/.bashrc that execs zsh on interactive
# login. Used when chsh and sss_override are both unavailable (e.g. AD user
# without sudo). Idempotent via sentinel comments; uninstall.sh removes the
# block. Mirrors the ~/.fzf.zsh machine-local file pattern.
write_bashrc_zsh_fallback() {
    local zsh_path="$1"
    local bashrc="$HOME/.bashrc"
    local sentinel="# >>> dotfiles managed (AD user shell fallback) >>>"
    local sentinel_end="# <<< dotfiles managed (AD user shell fallback) <<<"

    if grep -qF "$sentinel" "$bashrc" 2>/dev/null; then
        info "~/.bashrc zsh fallback block already present — skipping."
        return 0
    fi

    info "Writing zsh exec fallback to ~/.bashrc (chsh/sss_override unavailable)."
    cat >> "$bashrc" <<EOF

$sentinel
# chsh unavailable for directory-service user; replace login bash with zsh.
# Remove this block or run 'chsh -s $zsh_path' if you gain /etc/passwd access.
if [[ -z "\$ZSH_VERSION" && -t 1 ]] && [[ -x "$zsh_path" ]]; then
  export SHELL="$zsh_path"
  exec "$zsh_path" -l
fi
$sentinel_end
EOF
}

setup_shell() {
    title "Configuring shell"

    [[ -n "$(command -v brew)" ]] && zsh_path="$(brew --prefix)/bin/zsh" || zsh_path="$(which zsh)"

    # 1. /etc/shells — required by chsh and for SSSD shell validation.
    if ! grep -q "$zsh_path" /etc/shells 2>/dev/null; then
        info "adding $zsh_path to /etc/shells"
        if sudo -n true 2>/dev/null; then
            echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
        else
            warning "Cannot write to /etc/shells without sudo. Run as admin:"
            warning "  echo '$zsh_path' | sudo tee -a /etc/shells"
            warning "Then re-run './install.sh shell'."
        fi
    fi

    # 2. Already the target shell — nothing to do.
    if [[ "$SHELL" == "$zsh_path" ]]; then
        info "Login shell is already $zsh_path — nothing to do."
        return 0
    fi

    # 3. Tiered switch: local user -> chsh; AD/SSSD -> sss_override;
    #    fallback -> ~/.bashrc exec block (interactive terminals only).
    if is_directory_service_user; then
        info "User '$USER' is a directory-service user (not in /etc/passwd)."
        if grep -q "$zsh_path" /etc/shells 2>/dev/null && try_sss_override "$zsh_path"; then
            return 0
        fi
        warning "Falling back to ~/.bashrc zsh exec (interactive terminals only)."
        warning "\$SHELL stays $(basename "$SHELL"); non-interactive sessions (cron/ssh -c) stay bash."
        warning "For a real shell change: ask your AD admin to set loginShell='$zsh_path'."
        write_bashrc_zsh_fallback "$zsh_path"
    else
        if grep -q "$zsh_path" /etc/shells 2>/dev/null; then
            if chsh -s "$zsh_path"; then
                info "default shell changed to $zsh_path (takes effect on next login)."
            else
                error "chsh failed for local user '$USER'. Check the error above."
            fi
        else
            warning "Skipped chsh: $zsh_path is not in /etc/shells. Add it first (see above)."
        fi
    fi
}

# CodeGraph — pre-indexed code knowledge graph for AI agents (opencode, etc.).
# Not on Homebrew; the official installer bundles its own Node runtime and
# places `codegraph` on a user-level bin already on PATH (~/.local/bin, see
# zshenv.symlink). Idempotent: skips if `codegraph` is already on PATH.
# Per-project indexing (`codegraph init`) is NOT done here — only the global
# CLI. The opencode MCP wiring lives in config/opencode/opencode.json.
setup_codegraph() {
    title "Setting up CodeGraph"

    if command -v codegraph >/dev/null 2>&1; then
        info "codegraph already installed ($(codegraph --version 2>/dev/null || echo present)), skipping."
    else
        info "Installing CodeGraph via official installer (bundles its own Node runtime)."
        curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh
    fi
}

setup_ohmyzsh() {
    title "Configuring ohmyzsh"

    # Set defaults so the guards below work under bash (install.sh's shebang),
    # where $ZSH/$ZSH_CUSTOM are normally only set by zshrc in an interactive zsh.
    ZSH="${ZSH:-$DOTFILES/zsh/.oh-my-zsh}"
    ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH/custom}"

    # 检测关键文件而非仅目录——避免不完整安装（目录存在但 oh-my-zsh.sh 缺失，
    # 如先前 curl 失败留下空目录）被永远跳过。oh-my-zsh install.sh 在目标非空时
    # 会 abort，故先清理不完整目录。
    if ! [[ -f "$ZSH/oh-my-zsh.sh" ]]; then
        if [[ -d "$ZSH" ]]; then
            info "Removing incomplete oh-my-zsh directory (missing oh-my-zsh.sh)."
            rm -rf "$ZSH"
        fi
        info "install ohmyzsh"
        RUNZSH="no" KEEP_ZSHRC="yes" ZSH="$DOTFILES/zsh/.oh-my-zsh" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    else
        info "ohmyzsh already installed"
    fi

    if ! [[ -d "$ZSH_CUSTOM/themes/powerlevel10k" ]]; then
        info "install the theme of ohmyzsh"

        # install theme
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"

        # install custom plugins
        git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    else
        info "p10k have already installed"
    fi
}

case "$1" in
    backup)
        backup
        ;;
    link)
        setup_symlinks
        ;;
    git)
        setup_git
        ;;
    homebrew)
        setup_homebrew
        ;;
    ohmyzsh)
        setup_ohmyzsh
        ;;
    shell)
        setup_shell
        ;;
    codegraph)
        setup_codegraph
        ;;
    all)
        setup_symlinks
        setup_homebrew
        setup_git
        setup_ohmyzsh
        setup_shell
        setup_codegraph
        ;;
    *)
        echo -e $"\nUsage: $(basename "$0") {backup|link|git|homebrew|ohmyzsh|shell|codegraph|all}\n"
        exit 1
        ;;
esac

echo -e
success "Done."
