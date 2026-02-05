local data_home = vim.fn.tempname()
vim.fn.mkdir(data_home, "p")
vim.env.XDG_DATA_HOME = data_home
vim.env.XDG_STATE_HOME = data_home .. "/state"
vim.env.XDG_CACHE_HOME = data_home .. "/cache"
vim.fn.mkdir(vim.env.XDG_STATE_HOME, "p")
vim.fn.mkdir(vim.env.XDG_CACHE_HOME, "p")
vim.env.STEM_TMP_ROOT = data_home .. "/stem-tmp"
vim.env.STEM_TMP_UNTITLED_ROOT = data_home .. "/stem-untitled"

local root = vim.fn.fnamemodify(vim.fn.expand("<sfile>:p"), ":h:h")
vim.opt.rtp:prepend(root)
vim.g.stem_test_root = root

local plenary_candidates = {
  root .. "/.deps/plenary.nvim",
  vim.fn.stdpath "data" .. "/lazy/plenary.nvim",
  vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim"),
}
for _, path in ipairs(plenary_candidates) do
  if path and path ~= "" and vim.fn.isdirectory(path) == 1 then
    vim.opt.rtp:prepend(path)
    break
  end
end

-- Enable filetype and plugins for session behavior
vim.cmd("filetype plugin indent on")
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"

local test_util = require "tests.test_util"
test_util.cleanup_test_mounts()
test_util.reset_editor()
