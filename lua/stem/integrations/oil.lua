local constants = require "stem.constants"

local M = {}

-- Optional integration with the oil.nvim plugin.

local cached = nil

local function load_oil()
  if cached ~= nil then
    return cached
  end
  local ok, oil = pcall(require, "oil")
  cached = ok and oil or false
  return cached
end

function M.is_available(config)
  if config and config.oil and config.oil.enabled == false then
    return false
  end
  return load_oil() ~= false
end

function M.current_dir(bufnr, config)
  if not M.is_available(config) then
    return nil
  end
  local buf = bufnr or vim.api.nvim_get_current_buf()
  local bufname = vim.api.nvim_buf_get_name(buf)
  if vim.bo[buf].filetype ~= constants.oil.filetype
    and not (bufname and bufname:match(constants.oil.uri_pattern))
  then
    return nil
  end
  local oil = load_oil()
  if oil and oil.get_current_dir then
    return oil.get_current_dir()
  end
  return nil
end

function M.open_root(config, temp_root)
  if not M.is_available(config) then
    return
  end
  if not (config and config.oil and config.oil.follow) then
    return
  end
  if vim.bo.filetype ~= constants.oil.filetype then
    return
  end
  local oil = load_oil()
  if oil and oil.open then
    pcall(oil.open, temp_root)
  end
end

return M
