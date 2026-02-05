local M = {}

-- Workspace lifecycle helpers for state and mounts.

function M.remount_roots(state, ctx)
  if not state.temp_root then
    return
  end
  local allowed_root = state.temporary and ctx.config.workspace.temp_untitled_root or ctx.config.workspace.temp_root
  state.mounts = ctx.mount.clear_temp_root(state.temp_root, state.mounts, allowed_root)
  state.mounts, state.mount_map = ctx.mount.mount_roots(
    state.roots,
    state.temp_root,
    ctx.config.workspace.bindfs_args
  )
  if ctx.registry and ctx.registry.module then
    ctx.registry.module.set_mounts(ctx.registry.state, state.temp_root, state.mounts, state.mount_map)
  end
  if ctx.events then
    ctx.events.emit("mounts_changed", state)
  end
end

local function register_workspace(state, ctx)
  if not ctx.registry or not ctx.registry.module then
    return
  end
  local id = state.temp_root
  ctx.registry.module.register(ctx.registry.state, id, {
    id = id,
    name = state.name,
    temporary = state.temporary,
    roots = state.roots,
    temp_root = state.temp_root,
    mounts = state.mounts,
    mount_map = state.mount_map,
  })
  ctx.registry.module.set_current(ctx.registry.state, id)
end

-- Apply workspace state and mount roots.
function M.set_workspace(state, ctx, name, roots, temporary)
  state.name = name
  state.roots = roots or {}
  state.temporary = temporary
  state.temp_root = ctx.untitled.temp_root_for(ctx.config.workspace, name, temporary)
  M.remount_roots(state, ctx)
  state.prev_cwd = state.prev_cwd or vim.fn.getcwd()
  ctx.set_cwd(state.temp_root)
  ctx.open_root_in_oil(ctx.config, state.temp_root)
  register_workspace(state, ctx)
end

-- Ensure a temporary workspace exists.
function M.ensure_workspace(state, ctx)
  if state.temp_root then
    return
  end
  M.set_workspace(state, ctx, state.name, {}, true)
end

return M
