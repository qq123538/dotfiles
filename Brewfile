brew "xclip" # access to clipboard (similar to pbcopy/pbpaste)
brew "fd" # find alternative
brew "fzf" # Fuzzy file searcher, used in scripts and in vim
brew "git" # Git version control (latest version)
brew "grep" # grep (latest)
brew "lazygit" # a better git UI
brew "fastfetch" # pretty system info (neofetch successor; neofetch archived 2024-04)
brew "neovim" # A better vim
brew "python" # python (latest)
brew "ripgrep" # very fast file searcher
brew "tmux" # terminal multiplexer
brew "tpm" # the plugins manager of tmux
brew "gh"
brew "wget" # internet file retriever
brew "zsh" # zsh (latest)
brew "tldr" # simplified man pages
brew "cmake"
brew "tree-sitter-cli" # nvim-treesitter calls the tree-sitter CLI; brew version links system glibc 2.35, avoids pulling a prebuilt CLI needing 2.38+ on Ubuntu 22.04
brew "node@22" # NOT `node`: 26.x x86_64_linux bottles break when relocated into the shorter ~/brew prefix — the relocation gsub rewrites prefix strings inside libnode.so's embedded V8 snapshot + process.config JSON, corrupting both (V8_Fatal "unreachable code" at Isolate::Initialize). node@22's bottle survives relocation. node@22 is keg-only: PATH entry in zsh/zshenv.symlink puts its bin/ on PATH.
brew "repo"
brew "htop"
brew "opencode" # AI coding agent CLI/TUI; homebrew-core formula ships Linux bottles (no source build / compiler dep); version may lag anomalyco/tap but opencode self-updates. Config in config/opencode/ symlinked by install.sh link
brew "git-delta"
brew "atuin" # magical shell history (replaces fzf Ctrl-R history search)
brew "yazi" # terminal file manager (image preview, async I/O); launch with `y` / `yc`
brew "chafa" # terminal image renderer; yazi image-preview fallback on tmux (esp. WSL2 where no native GPU preview exists)
brew "translate-shell" # command-line translator (provides `trans`), Google Translate + more
