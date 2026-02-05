local ui = require "stem.ui"

local M = {}

-- Persistent storage for workspace root lists.
local function workspace_dir()
  local dir = vim.fn.stdpath "data" .. "/stem/workspaces"
  vim.fn.mkdir(dir, "p")
  return dir
end

-- Validate workspace name for filesystem safety.
function M.is_valid_name(name)
  return name and name ~= "" and name:match("^[%w%._%-]+$")
end

-- Resolve workspace file path.
function M.path(name)
  if not M.is_valid_name(name) then
    return nil
  end
  return workspace_dir() .. "/" .. name .. ".lua"
end

-- Load a workspace definition from disk.
function M.read(name)
  local path = M.path(name)
  if not path or vim.fn.filereadable(path) == 0 then
    return nil
  end
  local chunk, err = loadfile(path)
  if not chunk then
    ui.notify(string.format("Failed to load workspace %s: %s", name, err or "unknown error"), vim.log.levels.WARN)
    return nil
  end
  if setfenv then
    setfenv(chunk, {})
  end
  local ok, result = pcall(chunk)
  if not ok or type(result) ~= "table" then
    return nil
  end
  return result
end

-- Write a workspace definition to disk.
function M.write(name, roots)
  local path = M.path(name)
  if not path then
    ui.notify("Invalid workspace name: " .. tostring(name), vim.log.levels.ERROR)
    return false
  end
  local encoded = "return " .. vim.inspect({ roots = roots })
  vim.fn.writefile(vim.split(encoded, "\n"), path)
  return true
end

-- List saved workspace names.
function M.list()
  local dir = workspace_dir()
  local files = vim.fn.globpath(dir, "*.lua", false, true)
  local names = {}
  for _, file in ipairs(files) do
    local name = vim.fn.fnamemodify(file, ":t:r")
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

return M
