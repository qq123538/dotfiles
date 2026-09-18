-- init.lua — yazi init script, layered on top of the defaults.
-- Docs: https://yazi-rs.github.io/docs/configuration/init
-- Symlinked to ~/.config/yazi/init.lua by `install.sh link`.
--
-- zoxide plugin: `Z` in yazi jumps via the zoxide db (same db the shell's
-- `z`/`zi` commands use, fed by the chpwd hook in zsh/zoxide.zsh).
-- update_db = true also records dirs navigated *inside* yazi into the db.
require("zoxide"):setup({
  update_db = true,
})
