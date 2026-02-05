local constants = require "stem.constants"
local helpers = require "stem.gc.helpers"
local ui = require "stem.ui"

local M = {}

-- Garbage collector for orphaned bindfs mounts after crashes.

local function list_bindfs_mounts()
  local lines = vim.fn.systemlist({ constants.commands.mount, "-t", constants.mount.fuse_type })
  return helpers.parse_bindfs_mount_targets(lines)
end

local function path_is_under(path, root)
  if not path or not root or root == "" then
    return false
  end
  if path == root then
    return true
  end
  return path:sub(1, #root + 1) == root .. "/"
end

local function mounts_by_workspace(base_root, mounts)
  local grouped = {}
  if not base_root or base_root == "" then
    return grouped
  end
  local prefix = base_root .. "/"
  for _, target in ipairs(mounts) do
    if path_is_under(target, base_root) then
      local rel = target:sub(#prefix + 1)
      local name = rel:match("^([^/]+)")
      if name and name ~= "" then
        local ws_root = base_root .. "/" .. name
        grouped[ws_root] = grouped[ws_root] or {}
        table.insert(grouped[ws_root], target)
      end
    end
  end
  return grouped
end

function M.new(config, deps)
  local mount = deps.mount
  local untitled = deps.untitled
  local workspace_lock = deps.workspace_lock

  local collector = {}

  function collector.collect()
    local errors = {}
    local workspace_cfg = config.workspace or {}
    local named_root = workspace_cfg.temp_root
    local untitled_root = workspace_cfg.temp_untitled_root
    local bindfs_mounts = list_bindfs_mounts()
    local named_mounts = mounts_by_workspace(named_root, bindfs_mounts)
    local extra_untitled_roots = helpers.detect_untitled_roots(bindfs_mounts)
    local untitled_roots = {}
    if untitled_root and untitled_root ~= "" then
      untitled_roots[untitled_root] = true
    end
    for root in pairs(extra_untitled_roots) do
      untitled_roots[root] = true
    end

    if named_root and vim.fn.isdirectory(named_root) == 1 then
      local entries = vim.fn.readdir(named_root)
      for _, name in ipairs(entries) do
        if name ~= constants.names.locks_dir then
          local ws_root = named_root .. "/" .. name
          if vim.fn.isdirectory(ws_root) == 1 then
            local locked = workspace_lock and workspace_lock.has_locks(workspace_cfg, name)
            if not locked then
              local unmount_errors = mount.unmount_all(named_mounts[ws_root] or {})
              for _, err in ipairs(unmount_errors or {}) do
                table.insert(errors, err)
              end
              vim.fn.delete(ws_root, "rf")
            end
          end
        end
      end
    end

    for root in pairs(untitled_roots) do
      if root and vim.fn.isdirectory(root) == 1 then
        local lock_dir = root .. "/" .. constants.names.locks_dir
        local has_untitled_locks = helpers.has_live_locks(lock_dir)
        if not has_untitled_locks then
          local untitled_mounts = mounts_by_workspace(root, bindfs_mounts)
          local entries = vim.fn.readdir(root)
          for _, name in ipairs(entries) do
            if name ~= constants.names.locks_dir then
              local ws_root = root .. "/" .. name
              if vim.fn.isdirectory(ws_root) == 1 then
                local unmount_errors = mount.unmount_all(untitled_mounts[ws_root] or {})
                for _, err in ipairs(unmount_errors or {}) do
                  table.insert(errors, err)
                end
                vim.fn.delete(ws_root, "rf")
              end
            end
          end
        end
      end
    end
    if #errors > 0 then
      local lines = { constants.messages.gc_unmount_errors_header }
      for _, err in ipairs(errors) do
        if err and err.mount and err.error then
          table.insert(lines, string.format("- %s: %s", err.mount, err.error))
        end
      end
      ui.notify(table.concat(lines, "\n"), vim.log.levels.WARN)
    end
    return errors
  end

  return collector
end

return M
