local constants = require "stem.constants"
local oil = require "stem.integrations.oil"

local M = {}

-- Shared workspace core: state, mounts, buffers, and side effects.

local function normalize_dir(path)
  local expanded = vim.fn.expand(path)
  expanded = vim.fn.fnamemodify(expanded, ":p")
  expanded = expanded:gsub("/+$", "")
  return expanded
end

local function log_confirm_result(prompt, choice)
  vim.cmd(
    ("echomsg %s"):format(vim.fn.string("stem confirm: " .. prompt .. " -> " .. tostring(choice)))
  )
end

local function is_oil_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  if vim.bo[bufnr].filetype == constants.oil.filetype then
    return true
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  return name and name:match(constants.oil.uri_pattern) ~= nil
end

local function context_dir()
  local buf = vim.api.nvim_get_current_buf()
  local bufname = vim.api.nvim_buf_get_name(buf)
  local oil_dir = oil.current_dir(buf)
  if oil_dir and oil_dir ~= "" then
    return normalize_dir(oil_dir)
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
  local original_buf = buf
  if path == root then
    local target = temp_root .. "/" .. mount_name
    vim.cmd(constants.vim.edit_cmd .. vim.fn.fnameescape(target))
    local new_buf = vim.api.nvim_get_current_buf()
    if new_buf ~= original_buf and vim.api.nvim_buf_is_valid(original_buf) and not vim.bo[original_buf].modified then
      pcall(vim.api.nvim_buf_delete, original_buf, { force = false })
    end
    return
  end
  if path:sub(1, #root + 1) ~= root .. "/" then
    return
  end
  local rel = path:sub(#root + 2)
  local target = temp_root .. "/" .. mount_name .. "/" .. rel
  vim.cmd(constants.vim.edit_cmd .. vim.fn.fnameescape(target))
  local new_buf = vim.api.nvim_get_current_buf()
  if new_buf ~= original_buf and vim.api.nvim_buf_is_valid(original_buf) and not vim.bo[original_buf].modified then
    pcall(vim.api.nvim_buf_delete, original_buf, { force = false })
  end
end

function M.new(config, deps)
  local ui = deps.ui
  local mount = deps.mount
  local untitled = deps.untitled
  local workspace_lock = deps.workspace_lock
  local registry = deps.registry
  local events = deps.events
  local lifecycle = deps.lifecycle
  local effects = deps.effects
  local sessions = deps.sessions

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

  local core = {}

  function core.state()
    return state
  end

  function core.context_dir()
    return context_dir()
  end

  function core.bootstrap()
    if vim.env[constants.env.skip_bootstrap] == "1" then
      return
    end
    if vim.fn.executable(constants.commands.bindfs) ~= 1 then
      error(constants.messages.bootstrap_bindfs)
    end
    if vim.fn.filereadable("/dev/fuse") == 0 then
      error(constants.messages.bootstrap_fuse)
    end
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
    local allowed_root = state.temporary and config.workspace.temp_untitled_root or config.workspace.temp_root
    state.mounts = mount.clear_temp_root(state.temp_root, state.mounts, allowed_root)
    state.mount_map = {}
    registry.module.set_mounts(registry.state, id, {}, {})
    if events then
      events.emit(constants.events.workspace_unmounted, state)
    end
  end

  function core.mount_roots()
    lifecycle.remount_roots(state, {
      config = config,
      mount = mount,
      registry = registry,
      events = events,
    })
  end

  function core.set_workspace(name, roots, temporary)
    lifecycle.set_workspace(state, {
      config = config,
      mount = mount,
      untitled = untitled,
      registry = registry,
      events = events,
      set_cwd = effects.set_cwd,
      open_root_in_oil = effects.open_root_in_oil,
    }, name, roots, temporary)
  end

  function core.ensure_workspace()
    lifecycle.ensure_workspace(state, {
      config = config,
      mount = mount,
      untitled = untitled,
      registry = registry,
      events = events,
      set_cwd = effects.set_cwd,
      open_root_in_oil = effects.open_root_in_oil,
    })
  end

  function core.add(dir)
    local path = dir and dir ~= "" and normalize_dir(dir) or context_dir()
    if not path or path == "" then
      ui.notify(constants.messages.directory_required, vim.log.levels.ERROR)
      return
    end
    if vim.fn.isdirectory(path) == 0 then
      ui.notify(string.format(constants.messages.not_a_directory, path), vim.log.levels.ERROR)
      return
    end
    core.ensure_workspace()
    for _, root in ipairs(state.roots) do
      if root == path then
        ui.notify(string.format(constants.messages.already_added, path), vim.log.levels.WARN)
        return
      end
    end
    table.insert(state.roots, path)
    core.mount_roots()
    if registry and registry.module then
      registry.module.set_roots(registry.state, state.temp_root, state.roots)
    end
    maybe_reopen_in_workspace(state.temp_root, state.mount_map, path)
    ui.notify(string.format(constants.messages.added, path))
  end

  function core.remove(dir)
    if not dir or dir == "" then
      ui.notify(constants.messages.directory_required, vim.log.levels.ERROR)
      return
    end
    if not state.temp_root then
      ui.notify(constants.messages.no_workspace_open, vim.log.levels.ERROR)
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
        ui.notify(string.format(constants.messages.directory_not_found, dir), vim.log.levels.ERROR)
        return
      end
    end
    table.remove(state.roots, idx)
    core.mount_roots()
    if registry and registry.module then
      registry.module.set_roots(registry.state, state.temp_root, state.roots)
    end
    ui.notify(string.format(constants.messages.removed, path))
  end

  function core.close()
    if state.temporary and #state.roots > 0 and config.workspace.confirm_close and #vim.api.nvim_list_uis() > 0 then
      local choice = ui.confirm(constants.messages.close_unnamed_confirm, "&Yes\n&No", 2)
      log_confirm_result(constants.messages.close_unnamed_confirm, choice)
      if choice ~= 1 then
        return false
      end
    end
    local candidates = {}
    if registry and registry.module then
      local ws = registry.module.get_current(registry.state)
      if ws and ws.open_buffers then
        for bufnr in pairs(ws.open_buffers) do
          candidates[bufnr] = true
        end
      end
    end
    if state.temp_root then
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(bufnr) then
          local name = vim.api.nvim_buf_get_name(bufnr)
          if name and name ~= "" then
            local path = normalize_dir(name)
            if registry and registry.module then
              local ws = registry.module.find_by_path(registry.state, path)
              if ws and ws.id == state.temp_root then
                candidates[bufnr] = true
              end
            elseif path:sub(1, #state.temp_root) == state.temp_root then
              candidates[bufnr] = true
            end
          end
        end
      end
    end
    local modified = {}
    for bufnr in pairs(candidates) do
      if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].modified then
        table.insert(modified, bufnr)
      end
    end
    if #modified > 0 and #vim.api.nvim_list_uis() > 0 then
      local choice = ui.confirm(constants.messages.close_unsaved_confirm, "&Yes\n&No", 2)
      log_confirm_result(constants.messages.close_unsaved_confirm, choice)
      if choice ~= 1 then
        return false
      end
    end
    for bufnr in pairs(candidates) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        local force = vim.bo[bufnr].modified
        pcall(vim.api.nvim_buf_delete, bufnr, { force = force })
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
      local allowed_root = state.temporary and config.workspace.temp_untitled_root or config.workspace.temp_root
      state.mounts = mount.clear_temp_root(state.temp_root, state.mounts, allowed_root)
      vim.fn.delete(state.temp_root, "rf")
    end
    if state.temporary then
      untitled.cleanup_if_last(config.workspace)
    end
    if state.prev_cwd then
      local current_buf = vim.api.nvim_get_current_buf()
      if is_oil_buffer(current_buf) then
        local scratch = vim.api.nvim_create_buf(false, true)
        if vim.api.nvim_win_is_valid(0) then
          vim.api.nvim_win_set_buf(0, scratch)
        end
        pcall(vim.api.nvim_buf_delete, current_buf, { force = true })
      end
      effects.set_cwd(state.prev_cwd)
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
    ui.notify(constants.messages.workspace_closed)
    return true
  end

  function core.complete_roots(arg_lead)
    local matches = {}
    for _, item in ipairs(state.roots) do
      if arg_lead == "" or item:find(arg_lead, 1, true) == 1 then
        table.insert(matches, item)
      end
    end
    return matches
  end

  function core.on_buf_enter(bufnr)
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
      events.emit(constants.events.buffer_mapped, { workspace = ws, bufnr = bufnr })
    end
  end

  function core.on_buf_leave(bufnr)
    if not registry or not registry.module then
      return
    end
    local id = registry.module.remove_buffer(registry.state, bufnr)
    if not id then
      return
    end
    local ws = registry.module.register(registry.state, id, {})
    if events then
      events.emit(constants.events.buffer_unmapped, { workspace = ws, bufnr = bufnr })
    end
    vim.defer_fn(function()
      maybe_unmount_if_idle()
    end, 10)
  end

  core.on_buf_delete = core.on_buf_leave

  return core
end

return M
