-- Browser-based markdown preview (iamcco/markdown-preview.nvim).
-- Renders mermaid fences as interactive SVGs — VSCode-like experience.
-- Remote-host setup: fixed port 8090, browser launch is intercepted to
-- print the URL instead of spawning the (snap) firefox over X11. Open it
-- in your local browser via an SSH tunnel: ssh -L 8090:localhost:8090.
return {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    ft = { "markdown" },
    -- ":" prefix makes lazy.nvim load the plugin first (Loader.load), so the
    -- mkdp#... autoload function resolves. A function-style build calls
    -- vim.fn directly on an unloaded plugin and fails with E117.
    build = ":call mkdp#util#install()",
    init = function()
        vim.g.mkdp_port = "8090"
        vim.g.mkdp_theme = "dark"
        vim.g.mkdp_preview_options = {
            maid = {
                theme = "dark",
            },
        }
        vim.g.mkdp_auto_close = 0
        vim.g.mkdp_combine_preview = 1
        vim.g.mkdp_combine_preview_auto_refresh = 1
        vim.g.mkdp_echo_preview_url = 1
        -- Intercept the default browser launch: just notify the URL. On this
        -- remote host xdg-open would pull the snap firefox over X11, which
        -- is slow and unreliable — tunnel + local browser is the way to go.
        -- mkdp_browserfunc is invoked via nvim_call_function, which cannot
        -- resolve "v:lua." names (E117), so a Vimscript wrapper is required.
        _G.MkdpOpenBrowserNotify = function(url)
            vim.notify(
                ("%s\n ssh -L 8090:localhost:8090 后用本地浏览器打开"):format(url),
                vim.log.levels.INFO,
                {
                    title = "MarkdownPreview",
                }
            )
        end
        vim.cmd [[
            function! MkdpOpenBrowser(url) abort
                call v:lua.MkdpOpenBrowserNotify(a:url)
            endfunction
        ]]
        vim.g.mkdp_browserfunc = "MkdpOpenBrowser"
    end,
    keys = {
        { "<Leader>mp", "<Cmd>MarkdownPreviewToggle<CR>", desc = "Markdown browser preview" },
    },
}
