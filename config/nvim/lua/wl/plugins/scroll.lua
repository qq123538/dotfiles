return {
    {
        "karb94/neoscroll.nvim",
        config = function()
            -- require("neoscroll").setup {}
        end,
    },
    {
        "petertriho/nvim-scrollbar",
        event = "VeryLazy",
        config = function()
            -- local scrollbar = require("scrollbar")
            -- scrollbar.setup {
            --     show_in_active_only = true,
            --     handle = {
            --         blend = 0,
            --         color = "#1c1c1c",
            --     },
            -- }
            -- require("scrollbar.handlers.gitsigns").setup()
        end,
    },
}
