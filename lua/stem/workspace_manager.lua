local M = {}

local function normalize_dir(path)
  local expanded = vim.fn.expand(path)
  expanded = vim.fn.fnamemodify(expanded, ":p")
  expanded = expanded:gsub("/+$", "")
  return expanded
end

local function set_cwd(path)
  if not path or path == "" then
    return
  end
  vim.cmd("cd " .. vim.fn.fnameescape(path))
  vim.cmd("tcd " .. vim.fn.fnameescape(path))
end

local function open_root_in_oil(config, temp_root)
  if not config.oil.follow then
    return
  end
  if vim.bo.filetype ~= "oil" then
    return
  end
  local ok, oil = pcall(require, "oil")
  if ok then
    pcall(oil.open, temp_root)
  end
end

local function context_dir()
  local buf = vim.api.nvim_get_current_buf()
  local bufname = vim.api.nvim_buf_get_name(buf)
  if vim.bo[buf].filetype == "oil" or (bufname and bufname:match("^oil%-%w+://")) then
    local ok, oil = pcall(require, "oil")
    if ok and oil.get_current_dir then
      local oil_dir = oil.get_current_dir()
      if oil_dir and oil_dir ~= "" then
        return normalize_dir(oil_dir)
      end
    end
  end

  local name = vim.api.nvim_buf_get_name(buf)
  if name and name ~= "" then
    local path = normalize_dir(name)
    if vim.fn.isdirectory(path) == 1 then
      return path
    end
    local parent = normalize_dir(vim.fn.fnamemodify(path, ":h"))
    if parent ~= "" and vim.fn.isdirectory(parent) == 1 then
      return parent
    end
  end
  return normalize_dir(vim.fn.getcwd(0, 0))
end

local function complete_from_list(list, arg_lead)
  local matches = {}
  for _, item in ipairs(list) do
    if arg_lead == "" or item:find(arg_lead, 1, true) == 1 then
      table.insert(matches, item)
    end
  end
  return matches
end

local function complete_workspace_names(store, arg_lead)
  return complete_from_list(store.list(), arg_lead)
end

local function complete_rename(store, arg_lead, cmd_line)
  local args = vim.split(cmd_line, "%s+")
  if #args <= 2 then
    return complete_workspace_names(store, arg_lead)
  end
  return {}
end

local function maybe_reopen_in_workspace(temp_root, mount_map, root)
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  if not name or name == "" then
    return
  end
  local path = normalize_dir(name)
  local mount_name = mount_map[root]
  if not mount_name then
    return
  end
  if path == root then
    local target = temp_root .. "/" .. mount_name
    vim.cmd("edit " .. vim.fn.fnameescape(target))
    return
  end
  if path:sub(1, #root + 1) ~= root .. "/" then
    return
  end
  local rel = path:sub(#root + 2)
  local target = temp_root .. "/" .. mount_name .. "/" .. rel
  vim.cmd("edit " .. vim.fn.fnameescape(target))
end

function M.new(config, deps)
  local ui = deps.ui
  local store = deps.store
  local sessions = deps.sessions
  local mount = deps.mount
  local untitled = deps.untitled
  local workspace_lock = deps.workspace_lock
  local registry = deps.registry
  local events = deps.events

  local state = {
    name = nil,
    temporary = true,
    roots = {},
    temp_root = nil,
    prev_cwd = nil,
    mounts = {},
    mount_map = {},
    instance_id = tostring(vim.fn.getpid()),
  }

  local function bootstrap()
    if vim.env.STEM_SKIP_BOOTSTRAP == "1" then
      return
    end
    if vim.fn.executable("bindfs") ~= 1 then
      error("stem.nvim requires bindfs to be installed")
    end
    if vim.fn.filereadable("/dev/fuse") == 0 then
      error("stem.nvim requires FUSE (/dev/fuse) to be available")
    end
  end

  local function register_workspace()
    if not registry or not registry.module then
      return
    end
    local id = state.temp_root
    registry.module.register(registry.state, id, {
      id = id,
      name = state.name,
      temporary = state.temporary,
      roots = state.roots,
      temp_root = state.temp_root,
      mounts = state.mounts,
      mount_map = state.mount_map,
    })
    registry.module.set_current(registry.state, id)
  end

  local function maybe_unmount_if_idle()
    if not registry or not registry.module then
      return
    end
    local id = state.temp_root
    if not id then
      return
    end
    if registry.module.buffer_count(registry.state, id) > 0 then
      return
    end
    if state.temporary and untitled.has_locks(config.workspace) then
      return
    end
    if
      not state.temporary
      and workspace_lock
      and workspace_lock.has_other_locks(config.workspace, state.name, state.instance_id)
    then
      return
    end
    state.mounts = mount.clear_temp_root(state.temp_root, state.mounts)
    state.mount_map = {}
    registry.module.set_mounts(registry.state, id, {}, {})
    if events then
      events.emit("workspace_unmounted", state)
    end
  end

  local function mount_roots()
    if not state.temp_root then
      return
    end
    state.mounts = mount.clear_temp_root(state.temp_root, state.mounts)
    state.mounts, state.mount_map = mount.mount_roots(
      state.roots,
      state.temp_root,
      config.workspace.bindfs_args
    )
    if registry and registry.module then
      registry.module.set_mounts(registry.state, state.temp_root, state.mounts, state.mount_map)
    end
    if events then
      events.emit("mounts_changed", state)
    end
  end

  local function set_workspace(name, roots, temporary)
    state.name = name
    state.roots = roots or {}
    state.temporary = temporary
    state.temp_root = untitled.temp_root_for(config.workspace, name, temporary)
    mount_roots()
    state.prev_cwd = state.prev_cwd or vim.fn.getcwd()
    set_cwd(state.temp_root)
    open_root_in_oil(config, state.temp_root)
    register_workspace()
  end

  local function ensure_workspace()
    if state.temp_root then
      return
    end
    set_workspace(state.name, {}, true)
  end

  local manager = {}

  function manager.setup()
    bootstrap()
  end

  function manager.new(name)
    local base_dir = context_dir()
    local workspace_name = name ~= "" and name or nil
    set_workspace(workspace_name, {}, workspace_name == nil)
    if state.temporary then
      untitled.ensure_instance_lock(config.workspace, state.instance_id)
    else
      if workspace_lock then
        workspace_lock.ensure_instance_lock(config.workspace, workspace_name, state.instance_id)
      end
    end
    if config.workspace.auto_add_cwd and base_dir and base_dir ~= "" and base_dir ~= state.temp_root then
      manager.add(base_dir)
    end
    if workspace_name then
      ui.notify("Opened workspace: " .. workspace_name)
      sessions.load(workspace_name, config.session.enabled, config.session.auto_load)
    else
      ui.notify "Opened unnamed workspace"
    end
  end

  function manager.open(name)
    if not name or name == "" then
      ui.notify("Workspace name required", vim.log.levels.ERROR)
      return
    end
    local entry = store.read(name)
    if not entry or type(entry.roots) ~= "table" then
      ui.notify("Workspace not found: " .. name, vim.log.levels.ERROR)
      return
    end
    set_workspace(name, entry.roots, false)
    if workspace_lock then
      workspace_lock.ensure_instance_lock(config.workspace, name, state.instance_id)
    end
    ui.notify("Opened workspace: " .. name)
    sessions.load(name, config.session.enabled, config.session.auto_load)
  end

  function manager.save(name)
    local workspace_name = name ~= "" and name or state.name
    if not workspace_name or workspace_name == "" then
      workspace_name = vim.fn.input "Workspace name: "
    end
    if not workspace_name or workspace_name == "" then
      ui.notify("Save cancelled", vim.log.levels.WARN)
      return
    end
    if not store.is_valid_name(workspace_name) then
      ui.notify("Invalid workspace name: " .. workspace_name, vim.log.levels.ERROR)
      return
    end
    if not store.write(workspace_name, state.roots) then
      return
    end
    if state.temporary then
      untitled.release_instance_lock(config.workspace, state.instance_id)
    end
    state.name = workspace_name
    state.temporary = false
    if workspace_lock then
      workspace_lock.ensure_instance_lock(config.workspace, state.name, state.instance_id)
    end
    state.temp_root = untitled.temp_root_for(config.workspace, state.name, state.temporary)
    mount_roots()
    set_cwd(state.temp_root)
    register_workspace()
    ui.notify("Saved workspace: " .. workspace_name)
  end

  function manager.close()
    if state.temporary and #state.roots > 0 and config.workspace.confirm_close and #vim.api.nvim_list_uis() > 0 then
      local choice = ui.confirm("Close unnamed workspace without saving?", "&Yes\n&No", 2)
      if choice ~= 1 then
        return
      end
    end
    if state.name then
      sessions.save(state.name, config.session.enabled)
    end
    local keep_mounts = false
    if state.temporary then
      untitled.release_instance_lock(config.workspace, state.instance_id)
      keep_mounts = untitled.has_locks(config.workspace)
    else
      if workspace_lock then
        workspace_lock.release_instance_lock(config.workspace, state.name, state.instance_id)
        keep_mounts = workspace_lock.has_locks(config.workspace, state.name)
      end
    end
    if state.temp_root and not keep_mounts then
      state.mounts = mount.clear_temp_root(state.temp_root, state.mounts)
      vim.fn.delete(state.temp_root, "rf")
    end
    if state.temporary then
      untitled.cleanup_if_last(config.workspace)
    end
    if state.prev_cwd then
      set_cwd(state.prev_cwd)
    end
    if registry and registry.module then
      registry.module.remove(registry.state, state.temp_root)
      registry.module.set_current(registry.state, nil)
    end
    state.name = nil
    state.temporary = true
    state.roots = {}
    state.temp_root = nil
    state.prev_cwd = nil
    ui.notify "Workspace closed"
  end

  function manager.add(dir)
    local path = dir and dir ~= "" and normalize_dir(dir) or context_dir()
    if not path or path == "" then
      ui.notify("Directory required", vim.log.levels.ERROR)
      return
    end
    if vim.fn.isdirectory(path) == 0 then
      ui.notify("Not a directory: " .. path, vim.log.levels.ERROR)
      return
    end
    ensure_workspace()
    for _, root in ipairs(state.roots) do
      if root == path then
        ui.notify("Already added: " .. path, vim.log.levels.WARN)
        return
      end
    end
    table.insert(state.roots, path)
    mount_roots()
    if registry and registry.module then
      registry.module.set_roots(registry.state, state.temp_root, state.roots)
    end
    maybe_reopen_in_workspace(state.temp_root, state.mount_map, path)
    ui.notify("Added: " .. path)
  end

  function manager.remove(dir)
    if not dir or dir == "" then
      ui.notify("Directory required", vim.log.levels.ERROR)
      return
    end
    if not state.temp_root then
      ui.notify("No workspace open", vim.log.levels.ERROR)
      return
    end
    local path = normalize_dir(dir)
    local idx
    for i, root in ipairs(state.roots) do
      if root == path then
        idx = i
        break
      end
    end
    if not idx then
      local matches = {}
      for i, root in ipairs(state.roots) do
        if vim.fn.fnamemodify(root, ":t") == dir then
          table.insert(matches, i)
        end
      end
      if #matches == 1 then
        idx = matches[1]
      else
        ui.notify("Directory not found: " .. dir, vim.log.levels.ERROR)
        return
      end
    end
    table.remove(state.roots, idx)
    mount_roots()
    if registry and registry.module then
      registry.module.set_roots(registry.state, state.temp_root, state.roots)
    end
    ui.notify("Removed: " .. path)
  end

  function manager.rename(arg1, arg2)
    if arg2 then
      local entry = store.read(arg1)
      if not entry then
        ui.notify("Workspace not found: " .. arg1, vim.log.levels.ERROR)
        return
      end
      if not store.is_valid_name(arg2) then
        ui.notify("Invalid workspace name: " .. arg2, vim.log.levels.ERROR)
        return
      end
      local from_path = store.path(arg1)
      local to_path = store.path(arg2)
      if vim.fn.filereadable(to_path) == 1 then
        ui.notify("Workspace already exists: " .. arg2, vim.log.levels.ERROR)
        return
      end
      vim.fn.rename(from_path, to_path)
      if state.name == arg1 then
        state.name = arg2
        state.temporary = false
        state.temp_root = untitled.temp_root_for(config.workspace, state.name, state.temporary)
        mount_roots()
        set_cwd(state.temp_root)
        register_workspace()
      end
      ui.notify(string.format("Renamed workspace: %s -> %s", arg1, arg2))
      return
    end

    if not state.name then
      ui.notify("No workspace open", vim.log.levels.ERROR)
      return
    end
    local new_name = arg1
    if not new_name or new_name == "" then
      ui.notify("New name required", vim.log.levels.ERROR)
      return
    end
    if not store.is_valid_name(new_name) then
      ui.notify("Invalid workspace name: " .. new_name, vim.log.levels.ERROR)
      return
    end
    local current_file = store.path(state.name)
    local target_file = store.path(new_name)
    if current_file and vim.fn.filereadable(current_file) == 1 then
      if vim.fn.filereadable(target_file) == 1 then
        ui.notify("Workspace already exists: " .. new_name, vim.log.levels.ERROR)
        return
      end
      vim.fn.rename(current_file, target_file)
    else
      if not store.write(new_name, state.roots) then
        return
      end
    end
    state.name = new_name
    state.temporary = false
    state.temp_root = untitled.temp_root_for(config.workspace, state.name, state.temporary)
    mount_roots()
    set_cwd(state.temp_root)
    register_workspace()
    ui.notify("Renamed workspace to: " .. new_name)
  end

  function manager.list()
    local names = store.list()
    if #names == 0 then
      ui.notify "No saved workspaces"
      return
    end
    local lines = { "Workspaces:" }
    for _, name in ipairs(names) do
      local marker = state.name == name and " *" or ""
      table.insert(lines, " - " .. name .. marker)
    end
    ui.notify(table.concat(lines, "\n"))
  end

  function manager.untitled_list()
    local names = untitled.list(config.workspace)
    if #names == 0 then
      ui.notify "No untitled workspaces"
      return
    end
    local lines = { "Untitled workspaces:" }
    for _, name in ipairs(names) do
      local marker = state.temp_root and state.temp_root:match("/" .. vim.pesc(name) .. "$") and " *" or ""
      table.insert(lines, " - " .. name .. marker)
    end
    ui.notify(table.concat(lines, "\n"))
  end

  function manager.status()
    if not state.temp_root then
      ui.notify "No workspace open"
      return
    end
    local label = state.name or "undefined"
    ui.notify(string.format("Workspace: %s (%d roots)", label, #state.roots))
  end

  function manager.complete_workspaces(arg_lead)
    return complete_workspace_names(store, arg_lead)
  end

  function manager.complete_roots(arg_lead)
    return complete_from_list(state.roots, arg_lead)
  end

  function manager.complete_rename(arg_lead, cmd_line)
    return complete_rename(store, arg_lead, cmd_line)
  end

  function manager.state()
    return state
  end

  function manager.on_buf_enter(bufnr)
    if not registry or not registry.module then
      return
    end
    local name = vim.api.nvim_buf_get_name(bufnr)
    if not name or name == "" then
      return
    end
    local path = normalize_dir(name)
    local ws = registry.module.find_by_path(registry.state, path)
    if not ws then
      return
    end
    registry.module.add_buffer(registry.state, ws.id, bufnr)
    if events then
      events.emit("buffer_mapped", { workspace = ws, bufnr = bufnr })
    end
  end

  function manager.on_buf_leave(bufnr)
    if not registry or not registry.module then
      return
    end
    local id = registry.module.remove_buffer(registry.state, bufnr)
    if not id then
      return
    end
    local ws = registry.module.register(registry.state, id, {})
    if events then
      events.emit("buffer_unmapped", { workspace = ws, bufnr = bufnr })
    end
    maybe_unmount_if_idle()
  end

  manager.on_buf_delete = manager.on_buf_leave

  return manager
end

return M
