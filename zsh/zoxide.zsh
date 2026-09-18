# zoxide shell integration — smarter cd that learns your habits
# https://github.com/ajeetdsouza/zoxide
# This file is auto-sourced by zshrc.symlink (matches $DOTFILES/**/*.zsh glob).
# zoxide is installed by `./install.sh homebrew` (see Brewfile).
#
# `zoxide init zsh` prints a zsh script (functions `z`/`zi` + `__zoxide_hook`
# appended to chpwd_functions) that is eval'd into the current shell — same
# pattern as atuin. The hook runs `zoxide add` on every cd, building the
# persistent db at ~/.local/share/zoxide/db.zo (scored by frecency). yazi's
# built-in zoxide plugin (the `Z` key) reads the same db.
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi
