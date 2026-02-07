local constants = require "stem.constants"
local ui = require "stem.ui"

local M = {}

-- Persistent storage for workspace root lists.

local SCHEMA_VERSION = 1
local function workspace_dir()
  local dir = vim.fn.stdpath "data" .. "/" .. constants.paths.workspace_dir
  vim.fn.mkdir(dir, "p")
  return dir
end

-- Validate workspace name for filesystem safety.
function M.is_valid_name(name)
  return type(name) == "string" and name ~= "" and name:match("^[%w%._%-]+$") ~= nil
end

-- Resolve workspace file path.
function M.path(name)
  if not M.is_valid_name(name) then
    return nil
  end
  return workspace_dir() .. "/" .. name .. constants.files.workspace_ext
end

-- Load a workspace definition from disk.
function M.read(name)
  local path = M.path(name)
  if not path or vim.fn.filereadable(path) == 0 then
    return nil
  end
  local chunk, err = loadfile(path)
  if not chunk then
    ui.notify(string.format(constants.messages.failed_load_workspace, name, err or "unknown error"), vim.log.levels.WARN)
    return nil
  end
  if setfenv then
    setfenv(chunk, {})
  end
  local ok, result = pcall(chunk)
  if not ok or type(result) ~= "table" then
    return nil
  end
  if type(result.roots) ~= "table" then
    return nil
  end
  if result.version == nil then
    result.version = SCHEMA_VERSION
  end
  if type(result.version) ~= "number" then
    return nil
  end
  return result
end

-- Write a workspace definition to disk.
function M.write(name, roots)
  local path = M.path(name)
  if not path then
    ui.notify(string.format(constants.messages.invalid_workspace_name, tostring(name)), vim.log.levels.ERROR)
    return false
  end
  local encoded = "return " .. vim.inspect({ version = SCHEMA_VERSION, roots = roots })
  local lines = vim.split(encoded, "\n")
  local dir = vim.fn.fnamemodify(path, ":h")
  local tmp = dir .. "/" .. vim.fn.fnamemodify(path, ":t") .. "." .. vim.fn.getpid() .. constants.files.temp_ext
  local ok = pcall(vim.fn.writefile, lines, tmp)
  if not ok then
    ui.notify(string.format(constants.messages.failed_write_workspace, name), vim.log.levels.ERROR)
    return false
  end
  local renamed = vim.fn.rename(tmp, path)
  if renamed ~= 0 then
    vim.fn.delete(tmp)
    ui.notify(string.format(constants.messages.failed_save_workspace, name), vim.log.levels.ERROR)
    return false
  end
  return true
end

-- List saved workspace names.
function M.list()
  local dir = workspace_dir()
  local files = vim.fn.globpath(dir, "*" .. constants.files.workspace_ext, false, true)
  local names = {}
  for _, file in ipairs(files) do
    local name = vim.fn.fnamemodify(file, ":t:r")
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

-- Delete a saved workspace definition.
function M.delete(name)
  local path = M.path(name)
  if not path or vim.fn.filereadable(path) == 0 then
    return false
  end
  return vim.fn.delete(path) == 0
end

return M
