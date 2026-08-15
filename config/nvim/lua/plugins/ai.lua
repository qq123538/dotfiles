---@type LazySpec
return {
    {
        "yetone/avante.nvim",
        opts = {
            provider = "opencode",
            windows = {
                sidebar_header = { include_model = true },
                edit = { border = "rounded" },
                ask = { border = "rounded" },
            },
        },
    },
}
