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

  # Reap ssh connection-multiplexing masters after DISPLAY changes.
  #
  # A master pins the X11 display and xauth cookie it was created with --
  # ssh_config(5) ControlMaster: "the display and agent forwarded will be the
  # one belonging to the master connection". It also daemonizes (PPID 1), so it
  # outlives the `ssh -Y` that spawned it and stays reusable for ControlPersist.
  # After reattaching over a fresh `ssh -Y`, a reused master still forwards to
  # the now-dead display -> "Can't open display", even though $DISPLAY above is
  # correct. `-O stop` unlinks the socket so the next ssh builds a fresh master,
  # without killing sessions already riding on it (`-O exit` would kill them).
  # Reaping every cm-* socket (not just X11-forwarding hosts) costs a git/rsync
  # host at most one extra handshake, and avoids an `ssh -G` probe per socket.
  # Socket name comes from ControlPath `cm-%r@%h:%p`; if that pattern changes
  # the parse simply no-ops rather than breaking ssh.
  __reap_ssh_mux() {
    local s spec
    for s in ~/.ssh/cm-*(N=); do
      spec=${s:t}; spec=${spec#cm-}
      ssh -O stop -S "$s" -p "${spec##*:}" "${spec%:*}" >/dev/null 2>&1
    done
  }

  __refresh_display() {
    local d
    d=$(tmux show-environment DISPLAY 2>/dev/null) || return
    d=${d#DISPLAY=}
    if [[ -n "$d" && "$d" != "$DISPLAY" ]]; then
      export DISPLAY="$d"
      __reap_ssh_mux
    fi
  }
  add-zsh-hook precmd __refresh_display

  # Manual refresh for panes stuck in a long task (not at a prompt).
  trd() { __refresh_display; }
fi

# NOTE: the SSH-login tmux auto-attach lives at the TOP of zshrc.symlink, not
# here — it must run before the p10k instant prompt block (instant prompt
# redirects stdout for the rest of zshrc, so a `-t 1` guard here would always
# be false and attach would silently never fire).
