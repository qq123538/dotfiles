# tmux + ssh X11-forwarding DISPLAY refresh.
#
# `ssh -Y` in + `tmux attach` to an existing session leaves panes with a
# STALE $DISPLAY (tmux can't mutate env of already-running shells). tmux's
# `update-environment` (default includes DISPLAY) refreshes the *session*
# env on attach, but only NEW panes inherit it — old panes stay stale, so
# `ssh -Y <host> <gui>` from an old pane fails with "Can't open display".
#
# This precmd hook pulls the fresh DISPLAY from the tmux session env into
# the current shell on every prompt, so reattach + <Enter> restores X11
# forwarding in any existing pane. Auto-sourced by zshrc.symlink after
# oh-my-zsh; produces no output (safe with p10k instant prompt). No-op
# outside tmux.
if [[ -n "$TMUX" ]]; then
  autoload -Uz add-zsh-hook
  __refresh_display() {
    local d
    d=$(tmux show-environment DISPLAY 2>/dev/null) || return
    d=${d#DISPLAY=}
    [[ -n "$d" && "$d" != "$DISPLAY" ]] && export DISPLAY="$d"
  }
  add-zsh-hook precmd __refresh_display

  # Manual refresh for panes stuck in a long task (not at a prompt).
  trd() { __refresh_display; }
fi
