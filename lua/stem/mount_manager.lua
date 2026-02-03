local ui = require "stem.ui"

local M = {}

function M.unmount_all(mounts)
  if #mounts == 0 then
    return
  end
  for _, mount in ipairs(mounts) do
    if vim.fn.isdirectory(mount) == 1 then
      if vim.fn.executable("fusermount") == 1 then
        vim.fn.system { "fusermount", "-u", mount }
      else
        vim.fn.system { "umount", mount }
      end
    end
  end
end

function M.clear_temp_root(path, mounts)
  if not path or path == "" then
    return {}
  end
  if mounts and #mounts > 0 then
    M.unmount_all(mounts)
  end
  if vim.fn.isdirectory(path) == 0 then
    vim.fn.mkdir(path, "p")
    return {}
  end
  local entries = vim.fn.readdir(path)
  for _, entry in ipairs(entries) do
    vim.fn.delete(path .. "/" .. entry, "rf")
  end
  return {}
end

function M.mount_roots(roots, temp_root, bindfs_args)
  if not temp_root then
    return {}, {}
  end
  local mounts = {}
  local mount_map = {}
  local used = {}
  for _, root in ipairs(roots) do
    local name = vim.fn.fnamemodify(root, ":t")
    local mount_name = name
    local n = 2
    while used[mount_name] do
      mount_name = string.format("%s__%d", name, n)
      n = n + 1
    end
    used[mount_name] = true
    mount_map[root] = mount_name
    local mount_path = temp_root .. "/" .. mount_name
    if vim.fn.executable("bindfs") ~= 1 then
      ui.notify("bindfs not found; cannot mount workspace", vim.log.levels.ERROR)
      return mounts, mount_map
    end
    vim.fn.mkdir(mount_path, "p")
    local cmd = { "bindfs" }
    for _, arg in ipairs(bindfs_args or {}) do
      table.insert(cmd, arg)
    end
    table.insert(cmd, root)
    table.insert(cmd, mount_path)
    local out = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then
      ui.notify(string.format("Failed to bindfs %s: %s", root, out), vim.log.levels.WARN)
    else
      table.insert(mounts, mount_path)
    end
  end
  return mounts, mount_map
end

return M
