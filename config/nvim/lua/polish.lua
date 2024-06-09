-- complex keymap placed here
local opts = { noremap = true, silent = true }

-- Move text up and down
vim.keymap.set("v", "J", ":move '>+1<CR>gv-gv", opts)
vim.keymap.set("v", "K", ":move '<-2<CR>gv-gv", opts)
vim.keymap.set("v", "p", '"_dP', opts)
vim.keymap.set("n", "<A-o>", ":ClangdSwitchSourceHeader<cr>", opts)

-- vim.filetype.add {
--   extension = {
--     foo = "fooscript",
--   },
--   filename = {
--     ["Foofile"] = "fooscript",
--   },
--   pattern = {
--     ["~/%.config/foo/.*"] = "fooscript",
--   },
-- }
