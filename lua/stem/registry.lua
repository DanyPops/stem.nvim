local M = {}

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

function M.register(registry, id, data)
  local ws = ensure_workspace(registry, id)
  for k, v in pairs(data or {}) do
    ws[k] = v
  end
  return ws
end

function M.remove(registry, id)
  registry.workspaces[id] = nil
end

function M.set_current(registry, id)
  registry.current_id = id
end

function M.get_current(registry)
  if not registry.current_id then
    return nil
  end
  return registry.workspaces[registry.current_id]
end

function M.list_ids(registry)
  local ids = {}
  for id in pairs(registry.workspaces) do
    table.insert(ids, id)
  end
  table.sort(ids)
  return ids
end

function M.set_roots(registry, id, roots)
  local ws = ensure_workspace(registry, id)
  ws.roots = roots or {}
end

function M.set_mounts(registry, id, mounts, mount_map)
  local ws = ensure_workspace(registry, id)
  ws.mounts = mounts or {}
  ws.mount_map = mount_map or {}
end

function M.add_buffer(registry, id, bufnr)
  local ws = ensure_workspace(registry, id)
  ws.open_buffers[bufnr] = true
  registry.buffer_map[bufnr] = id
end

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

function M.find_by_path(registry, path)
  for _, ws in pairs(registry.workspaces) do
    if ws.temp_root and path:sub(1, #ws.temp_root) == ws.temp_root then
      return ws
    end
  end
  return nil
end

return M
local M = {}

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

function M.register(registry, id, data)
  local ws = ensure_workspace(registry, id)
  for k, v in pairs(data or {}) do
    ws[k] = v
  end
  return ws
end

function M.remove(registry, id)
  registry.workspaces[id] = nil
end

function M.set_current(registry, id)
  registry.current_id = id
end

function M.get_current(registry)
  if not registry.current_id then
    return nil
  end
  return registry.workspaces[registry.current_id]
end

function M.list_ids(registry)
  local ids = {}
  for id in pairs(registry.workspaces) do
    table.insert(ids, id)
  end
  table.sort(ids)
  return ids
end

function M.set_roots(registry, id, roots)
  local ws = ensure_workspace(registry, id)
  ws.roots = roots or {}
end

function M.set_mounts(registry, id, mounts, mount_map)
  local ws = ensure_workspace(registry, id)
  ws.mounts = mounts or {}
  ws.mount_map = mount_map or {}
end

function M.add_buffer(registry, id, bufnr)
  local ws = ensure_workspace(registry, id)
  ws.open_buffers[bufnr] = true
  registry.buffer_map[bufnr] = id
end

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

function M.find_by_path(registry, path)
  for _, ws in pairs(registry.workspaces) do
    if ws.temp_root and path:sub(1, #ws.temp_root) == ws.temp_root then
      return ws
    end
  end
  return nil
end

return M
