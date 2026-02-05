local ui = require "stem.ui"

local M = {}

-- Mount lifecycle helpers for bindfs-backed roots.
local function normalize(path)
  local expanded = vim.fn.fnamemodify(path, ":p")
  return expanded:gsub("/+$", "")
end

local function is_under(path, root)
  if not path or not root or root == "" then
    return false
  end
  if path == root then
    return true
  end
  return path:sub(1, #root + 1) == root .. "/"
end

-- Unmount a list of mount paths.
function M.unmount_all(mounts)
  local errors = {}
  if #mounts == 0 then
    return errors
  end
  for _, mount in ipairs(mounts) do
    if vim.fn.isdirectory(mount) == 1 then
      local cmd = vim.fn.executable("fusermount") == 1 and { "fusermount", "-u", mount } or { "umount", mount }
      local out = vim.fn.system(cmd)
      if vim.v.shell_error ~= 0 then
        table.insert(errors, { mount = mount, cmd = cmd, error = out })
      end
    end
  end
  return errors
end

-- Clear temp root contents and unmount prior mounts.
function M.clear_temp_root(path, mounts, allowed_root)
  local errors = {}
  if not path or path == "" then
    table.insert(errors, { path = path, error = "invalid path" })
    return {}, errors
  end
  if allowed_root and allowed_root ~= "" then
    local normalized = normalize(path)
    local allowed = normalize(allowed_root)
    if not is_under(normalized, allowed) then
      table.insert(errors, { path = path, allowed_root = allowed_root, error = "unsafe path" })
      return {}, errors
    end
  end
  if mounts and #mounts > 0 then
    local unmount_errors = M.unmount_all(mounts)
    for _, err in ipairs(unmount_errors) do
      table.insert(errors, err)
    end
  end
  if vim.fn.isdirectory(path) == 0 then
    vim.fn.mkdir(path, "p")
    return {}, errors
  end
  local entries = vim.fn.readdir(path)
  for _, entry in ipairs(entries) do
    vim.fn.delete(path .. "/" .. entry, "rf")
  end
  return {}, errors
end

-- Mount roots into temp_root and return mounts/map.
function M.mount_roots(roots, temp_root, bindfs_args)
  local errors = {}
  if not temp_root then
    table.insert(errors, { error = "missing temp_root" })
    return {}, {}, errors
  end
  local mounts = {}
  local mount_map = {}
  local used = {}
  if vim.fn.executable("bindfs") ~= 1 then
    ui.notify("bindfs not found; cannot mount workspace", vim.log.levels.ERROR)
    table.insert(errors, { error = "bindfs missing" })
    return mounts, mount_map, errors
  end
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
    if vim.fn.isdirectory(root) == 0 then
      table.insert(errors, { root = root, error = "not a directory" })
      goto continue
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
      table.insert(errors, { root = root, cmd = cmd, error = out })
    else
      table.insert(mounts, mount_path)
    end
    ::continue::
  end
  return mounts, mount_map, errors
end

return M
