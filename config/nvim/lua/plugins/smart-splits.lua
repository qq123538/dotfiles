return {
    "mrjones2014/smart-splits.nvim",
    lazy = false, -- 官方强烈建议不要 lazy load: 依赖 @pane-is-vim tmux 变量, lazy 不加载则不 set
    opts = {
        ignored_buftypes = { "nofile", "quickfix", "prompt" },
        ignored_filetypes = { "neo-tree", "neo-tree-popup", "aerial", "toggleterm" },
        default_amount = 3,
        at_edge = "wrap",
        cursor_follows_swap = false,
        move_cursor_same_row = false,
        float_win_behavior = "previous",
        multiplexer_integration = "tmux",
    },
    specs = {
        {
            "AstroNvim/astrocore",
            opts = function(_, opts)
                local maps = opts.mappings
                -- 完全 disable AstroNvim 默认绑的 Ctrl 系列 + Ctrl Arrow 系列, 避免双套并存
                maps.n["<C-H>"] = false
                maps.n["<C-J>"] = false
                maps.n["<C-K>"] = false
                maps.n["<C-L>"] = false
                maps.n["<C-Up>"] = false
                maps.n["<C-Down>"] = false
                maps.n["<C-Left>"] = false
                maps.n["<C-Right>"] = false
            end,
        },
    },
    keys = {
        -- 跨边界导航 (Alt + 小写, 沿用原 tmux.nvim 习惯)
        { "<A-h>", function() require("smart-splits").move_cursor_left() end,  desc = "Move to left split" },
        { "<A-j>", function() require("smart-splits").move_cursor_down() end,  desc = "Move to below split" },
        { "<A-k>", function() require("smart-splits").move_cursor_up() end,    desc = "Move to above split" },
        { "<A-l>", function() require("smart-splits").move_cursor_right() end, desc = "Move to right split" },
        -- 跨边界 resize (Alt + 大写, 沿用原 tmux.nvim 习惯)
        { "<A-H>", function() require("smart-splits").resize_left() end,  desc = "Resize split left" },
        { "<A-J>", function() require("smart-splits").resize_down() end,  desc = "Resize split down" },
        { "<A-K>", function() require("smart-splits").resize_up() end,    desc = "Resize split up" },
        { "<A-L>", function() require("smart-splits").resize_right() end, desc = "Resize split right" },
        -- swap_buf (官方推荐键位: 交换当前窗口与方向窗口的 buffer, 不动位置)
        { "<Leader><Leader>h", function() require("smart-splits").swap_buf_left() end,  desc = "Swap buffer with left" },
        { "<Leader><Leader>j", function() require("smart-splits").swap_buf_down() end,  desc = "Swap buffer with below" },
        { "<Leader><Leader>k", function() require("smart-splits").swap_buf_up() end,    desc = "Swap buffer with above" },
        { "<Leader><Leader>l", function() require("smart-splits").swap_buf_right() end, desc = "Swap buffer with right" },
    },
}