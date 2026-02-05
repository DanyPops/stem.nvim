local dir = vim.fn.fnamemodify(vim.fn.expand("<sfile>:p"), ":h")
vim.g.stem_test_oil = true
vim.g.stem_test_oil_dir = vim.fn.getcwd()
vim.g.stem_test_oil_opened = nil
package.preload.oil = function()
  return {
    get_current_dir = function()
      return vim.g.stem_test_oil_dir
    end,
    open = function(path)
      vim.g.stem_test_oil_opened = path
    end,
  }
end
dofile(dir .. "/minimal_init.lua")
