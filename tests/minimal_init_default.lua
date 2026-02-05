local dir = vim.fn.fnamemodify(vim.fn.expand("<sfile>:p"), ":h")
vim.g.stem_test_oil = false
dofile(dir .. "/minimal_init.lua")
