return {
  "nvim-neo-tree/neo-tree.nvim",
  specs = {
    {
      "AstroNvim/astrocore",
      opts = function(_, opts)
        local m = opts.mappings
        m.n["<Leader>e"] = { "<Cmd>Neotree toggle<CR>", desc = "Toggle Explorer" }
        m.n["<Leader>r"] = { "<Cmd>Neotree focus reveal<CR>", desc = "Reveal current file in Explorer" }
        m.n["<Leader>o"] = false
      end,
    },
  },
  opts = {
    window = {
      position = "float",
      popup = {
        title = "  File Explorer  ",
        size = { height = "80%", width = "60%" },
        position = "50%",
        border = "rounded",
      },
    },
    filesystem = {
      follow_current_file = { enabled = false },
    },
  },
}