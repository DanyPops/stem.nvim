local constants = require "stem.constants"

local M = {}

-- Side-effect helpers for workspace operations.

-- Set global and tab-local cwd.
function M.set_cwd(path)
  if not path or path == "" then
    return
  end
  vim.cmd(constants.vim.cd_cmd .. vim.fn.fnameescape(path))
  vim.cmd(constants.vim.tcd_cmd .. vim.fn.fnameescape(path))
end

-- Reopen root in oil when following workspace.
function M.open_root_in_oil(config, temp_root)
  if not config.oil.follow then
    return
  end
  if vim.bo.filetype ~= constants.oil.filetype then
    return
  end
  local ok, oil = pcall(require, "oil")
  if ok then
    pcall(oil.open, temp_root)
  end
end

return M
