local constants = require "stem.constants"

local M = {}

-- Shared helpers for garbage collection and tests.

function M.parse_bindfs_mount_targets(lines)
  local targets = {}
  for _, line in ipairs(lines or {}) do
    local target = line:match(" on (%S+)" .. constants.mount.mount_type_pattern)
    if target and target ~= "" then
      table.insert(targets, target)
    end
  end
  return targets
end

function M.detect_untitled_roots(targets)
  local roots = {}
  for _, target in ipairs(targets or {}) do
    local prefix = target:match("^(.*)/stem%-untitled/[^/]+/[^/]+$")
    if not prefix then
      prefix = target:match("^(.*)/stem%-untitled/[^/]+$")
    end
    if prefix then
      roots[prefix .. "/stem-untitled"] = true
    end
  end
  return roots
end

function M.is_pid_alive(pid)
  if not pid or pid == "" then
    return false
  end
  if not tostring(pid):match("^%d+$") then
    return true
  end
  vim.fn.system({ constants.commands.kill, constants.process.kill_check_args[1], tostring(pid) })
  return vim.v.shell_error == 0
end

function M.has_live_locks(lock_dir)
  if vim.fn.isdirectory(lock_dir) == 0 then
    return false
  end
  local entries = vim.fn.readdir(lock_dir)
  local has_locks = false
  for _, entry in ipairs(entries) do
    if M.is_pid_alive(entry) then
      has_locks = true
    else
      vim.fn.delete(lock_dir .. "/" .. entry)
    end
  end
  return has_locks
end

return M
