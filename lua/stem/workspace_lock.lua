local M = {}

local function lock_root(config)
  local dir = config.temp_root .. "/.locks"
  vim.fn.mkdir(dir, "p")
  return dir
end

local function lock_dir(config, name)
  local dir = lock_root(config) .. "/" .. name
  vim.fn.mkdir(dir, "p")
  return dir
end

local function is_pid_alive(pid)
  if not pid or pid == "" then
    return false
  end
  if not tostring(pid):match("^%d+$") then
    return true
  end
  vim.fn.system({ "kill", "-0", tostring(pid) })
  return vim.v.shell_error == 0
end

local function prune_stale_locks(config, name)
  if not name or name == "" then
    return
  end
  local dir = lock_root(config) .. "/" .. name
  if vim.fn.isdirectory(dir) == 0 then
    return
  end
  local entries = vim.fn.readdir(dir)
  for _, entry in ipairs(entries) do
    if not is_pid_alive(entry) then
      vim.fn.delete(dir .. "/" .. entry)
    end
  end
end

function M.instance_lock_path(config, name, instance_id)
  return lock_dir(config, name) .. "/" .. instance_id
end

function M.ensure_instance_lock(config, name, instance_id)
  if not name or name == "" then
    return
  end
  prune_stale_locks(config, name)
  vim.fn.writefile({ os.date("!%Y-%m-%dT%H:%M:%SZ") }, M.instance_lock_path(config, name, instance_id))
end

function M.release_instance_lock(config, name, instance_id)
  if not name or name == "" then
    return
  end
  vim.fn.delete(M.instance_lock_path(config, name, instance_id))
  local dir = lock_root(config) .. "/" .. name
  if vim.fn.isdirectory(dir) == 1 then
    local entries = vim.fn.readdir(dir)
    if #entries == 0 then
      vim.fn.delete(dir, "d")
    end
  end
end

function M.has_locks(config, name)
  if not name or name == "" then
    return false
  end
  prune_stale_locks(config, name)
  local dir = lock_root(config) .. "/" .. name
  if vim.fn.isdirectory(dir) == 0 then
    return false
  end
  local locks = vim.fn.globpath(dir, "*", false, true)
  return #locks > 0
end

function M.has_other_locks(config, name, instance_id)
  if not name or name == "" then
    return false
  end
  prune_stale_locks(config, name)
  local dir = lock_root(config) .. "/" .. name
  if vim.fn.isdirectory(dir) == 0 then
    return false
  end
  local entries = vim.fn.readdir(dir)
  for _, entry in ipairs(entries) do
    if entry ~= instance_id then
      return true
    end
  end
  return false
end

return M
