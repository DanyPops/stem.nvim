local workspace_store = require "stem.workspace_store"

local M = {}

-- Session save/load helpers for named workspaces.
local function session_dir()
  local dir = vim.fn.stdpath "data" .. "/stem/sessions"
  vim.fn.mkdir(dir, "p")
  return dir
end

local function session_file(name)
  if not workspace_store.is_valid_name(name) then
    return nil
  end
  return session_dir() .. "/" .. name .. ".vim"
end

-- Load session file if enabled and present.
function M.load(name, enabled, auto_load)
  if not enabled or not auto_load then
    return
  end
  local path = session_file(name)
  if not path or vim.fn.filereadable(path) == 0 then
    return
  end
  vim.cmd("silent! source " .. vim.fn.fnameescape(path))
end

-- Save a session file if enabled.
function M.save(name, enabled)
  if not enabled then
    return
  end
  local path = session_file(name)
  if not path then
    return
  end
  vim.cmd("silent! mksession! " .. vim.fn.fnameescape(path))
end

return M
