local constants = require "stem.constants"
local lock_utils = require "stem.lock_utils"

local M = {}

-- Named workspace instance locks and stale cleanup.
local function lock_root(config)
  local dir = config.temp_root .. "/" .. constants.names.locks_dir
  return lock_utils.ensure_dir(dir)
end

local function lock_dir(config, name)
  local dir = lock_root(config) .. "/" .. name
  return lock_utils.ensure_dir(dir)
end

local function is_pid_alive(pid)
  if not pid or pid == "" then
    return false
  end
  if not tostring(pid):match("^%d+$") then
    return true
  end
  vim.fn.system({ constants.commands.kill, constants.process.kill_check_args[1], tostring(pid) })
  return vim.v.shell_error == 0
end

local function prune_stale_locks(config, name)
  if not name or name == "" then
    return
  end
  local dir = lock_root(config) .. "/" .. name
  local entries = lock_utils.list_dir(dir)
  for _, entry in ipairs(entries) do
    if not is_pid_alive(entry) then
      lock_utils.remove_lock(dir .. "/" .. entry)
    end
  end
end

-- Path for a named workspace lock file.
function M.instance_lock_path(config, name, instance_id)
  return lock_dir(config, name) .. "/" .. instance_id
end

-- Create lock for a named workspace instance.
function M.ensure_instance_lock(config, name, instance_id)
  if not name or name == "" then
    return
  end
  prune_stale_locks(config, name)
  lock_utils.write_lock(M.instance_lock_path(config, name, instance_id))
end

-- Release lock for a named workspace instance.
function M.release_instance_lock(config, name, instance_id)
  if not name or name == "" then
    return
  end
  lock_utils.remove_lock(M.instance_lock_path(config, name, instance_id))
  local dir = lock_root(config) .. "/" .. name
  if vim.fn.isdirectory(dir) == 1 then
    local entries = lock_utils.list_dir(dir)
    if #entries == 0 then
      vim.fn.delete(dir, "d")
    end
  end
end

-- Check if any locks exist for a workspace.
function M.has_locks(config, name)
  if not name or name == "" then
    return false
  end
  prune_stale_locks(config, name)
  local dir = lock_root(config) .. "/" .. name
  if vim.fn.isdirectory(dir) == 0 then
    return false
  end
  local locks = lock_utils.list_glob(dir)
  return #locks > 0
end

-- Check if other instances hold a lock.
function M.has_other_locks(config, name, instance_id)
  if not name or name == "" then
    return false
  end
  prune_stale_locks(config, name)
  local dir = lock_root(config) .. "/" .. name
  if vim.fn.isdirectory(dir) == 0 then
    return false
  end
  local entries = lock_utils.list_dir(dir)
  for _, entry in ipairs(entries) do
    if entry ~= instance_id then
      return true
    end
  end
  return false
end

return M
