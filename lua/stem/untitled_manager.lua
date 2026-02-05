local lock_utils = require "stem.lock_utils"

local M = {}

-- Untitled workspace naming and lock cleanup.
local function temp_untitled_root(config)
  local dir = config.temp_untitled_root
  return lock_utils.ensure_dir(dir)
end

local function lock_dir(config)
  local dir = temp_untitled_root(config) .. "/.locks"
  return lock_utils.ensure_dir(dir)
end

-- Path for an instance lock file.
function M.instance_lock_path(config, instance_id)
  return lock_dir(config) .. "/" .. instance_id
end

-- Create an instance lock file.
function M.ensure_instance_lock(config, instance_id)
  lock_utils.write_lock(M.instance_lock_path(config, instance_id))
end

-- Remove an instance lock file.
function M.release_instance_lock(config, instance_id)
  lock_utils.remove_lock(M.instance_lock_path(config, instance_id))
end

-- Find the next available untitled name.
function M.next_untitled_name(config)
  local base = temp_untitled_root(config)
  local files = vim.fn.globpath(base, "*", false, true)
  local used = {}
  for _, path in ipairs(files) do
    local name = vim.fn.fnamemodify(path, ":t")
    if name:match("^untitled%d*$") then
      used[name] = true
    end
  end
  if not used.untitled then
    return "untitled"
  end
  local i = 1
  while used["untitled" .. i] do
    i = i + 1
  end
  return "untitled" .. i
end

-- Cleanup untitled roots if no locks remain.
function M.cleanup_if_last(config)
  local locks = vim.fn.globpath(lock_dir(config), "*", false, true)
  if #locks > 0 then
    return
  end
  local base = temp_untitled_root(config)
  local entries = lock_utils.list_dir(base)
  for _, entry in ipairs(entries) do
    if entry ~= ".locks" then
      vim.fn.delete(base .. "/" .. entry, "rf")
    end
  end
end

-- List existing untitled workspaces.
function M.list(config)
  local base = temp_untitled_root(config)
  local names = {}
  local entries = lock_utils.list_dir(base)
  for _, entry in ipairs(entries) do
    if entry ~= ".locks" then
      table.insert(names, entry)
    end
  end
  table.sort(names)
  return names
end

-- Check if any untitled instance locks exist.
function M.has_locks(config)
  local locks = lock_utils.list_glob(lock_dir(config))
  return #locks > 0
end

-- Resolve temp root for named or untitled workspaces.
function M.temp_root_for(config, name, temporary)
  local base = config.temp_root
  vim.fn.mkdir(base, "p")
  if temporary and (not name or name == "") then
    local temp_base = temp_untitled_root(config)
    return temp_base .. "/" .. M.next_untitled_name(config)
  end
  return base .. "/" .. name
end

return M
