local M = {}

-- Registry holds workspace metadata and buffer associations.

-- Create an empty registry state.
function M.new()
  return {
    workspaces = {},
    buffer_map = {},
    current_id = nil,
  }
end

local function ensure_workspace(registry, id)
  if not registry.workspaces[id] then
    registry.workspaces[id] = {
      id = id,
      roots = {},
      mounts = {},
      mount_map = {},
      open_buffers = {},
    }
  end
  return registry.workspaces[id]
end

-- Register or update workspace metadata.
function M.register(registry, id, data)
  local ws = ensure_workspace(registry, id)
  for k, v in pairs(data or {}) do
    ws[k] = v
  end
  return ws
end

-- Remove a workspace from registry.
function M.remove(registry, id)
  registry.workspaces[id] = nil
end

-- Mark the current workspace id.
function M.set_current(registry, id)
  registry.current_id = id
end

-- Fetch current workspace metadata.
function M.get_current(registry)
  if not registry.current_id then
    return nil
  end
  return registry.workspaces[registry.current_id]
end

-- List known workspace ids.
function M.list_ids(registry)
  local ids = {}
  for id in pairs(registry.workspaces) do
    table.insert(ids, id)
  end
  table.sort(ids)
  return ids
end

-- Update workspace roots list.
function M.set_roots(registry, id, roots)
  local ws = ensure_workspace(registry, id)
  ws.roots = roots or {}
end

-- Update mounts and root->mount mapping.
function M.set_mounts(registry, id, mounts, mount_map)
  local ws = ensure_workspace(registry, id)
  ws.mounts = mounts or {}
  ws.mount_map = mount_map or {}
end

-- Track a buffer as belonging to a workspace.
function M.add_buffer(registry, id, bufnr)
  local ws = ensure_workspace(registry, id)
  ws.open_buffers[bufnr] = true
  registry.buffer_map[bufnr] = id
end

-- Untrack a buffer and return its workspace id.
function M.remove_buffer(registry, bufnr)
  local id = registry.buffer_map[bufnr]
  if not id then
    return nil
  end
  local ws = registry.workspaces[id]
  if ws then
    ws.open_buffers[bufnr] = nil
  end
  registry.buffer_map[bufnr] = nil
  return id
end

-- Count tracked buffers for a workspace.
function M.buffer_count(registry, id)
  local ws = registry.workspaces[id]
  if not ws then
    return 0
  end
  local count = 0
  for _ in pairs(ws.open_buffers) do
    count = count + 1
  end
  return count
end

-- Find workspace by absolute path prefix.
function M.find_by_path(registry, path)
  for _, ws in pairs(registry.workspaces) do
    if ws.temp_root and path:sub(1, #ws.temp_root) == ws.temp_root then
      return ws
    end
  end
  return nil
end

return M
