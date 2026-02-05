local constants = require "stem.constants"

local M = {}

-- Manager for titled (named) workspaces.

local function complete_from_list(list, arg_lead)
  local matches = {}
  for _, item in ipairs(list) do
    if arg_lead == "" or item:find(arg_lead, 1, true) == 1 then
      table.insert(matches, item)
    end
  end
  return matches
end

local function complete_rename(store, arg_lead, cmd_line)
  local args = vim.split(cmd_line, "%s+")
  if #args <= 2 then
    return complete_from_list(store.list(), arg_lead)
  end
  return {}
end

function M.new(core, deps)
  local ui = deps.ui
  local store = deps.store
  local sessions = deps.sessions
  local workspace_lock = deps.workspace_lock
  local untitled = deps.untitled
  local config = deps.config

  local titled = {}

  function titled.new_named(name)
    core.set_workspace(name, {}, false)
    if workspace_lock then
      workspace_lock.ensure_instance_lock(config.workspace, name, core.state().instance_id)
    end
    ui.notify(string.format(constants.messages.open_workspace, name))
    sessions.load(name, config.session.enabled, config.session.auto_load)
  end

  function titled.open(name)
    if not name or name == "" then
      ui.notify(constants.messages.workspace_name_required, vim.log.levels.ERROR)
      return
    end
    local entry = store.read(name)
    if not entry or type(entry.roots) ~= "table" then
      ui.notify(string.format(constants.messages.workspace_not_found, name), vim.log.levels.ERROR)
      return
    end
    local missing = {}
    local roots = {}
    for _, root in ipairs(entry.roots) do
      if vim.fn.isdirectory(root) == 1 then
        table.insert(roots, root)
      else
        table.insert(missing, root)
      end
    end
    if #missing > 0 then
      ui.notify(
        constants.messages.missing_roots .. "\n" .. constants.ui.list_item_prefix
          .. table.concat(missing, "\n" .. constants.ui.list_item_prefix),
        vim.log.levels.ERROR
      )
      store.write(name, roots)
    end
    core.set_workspace(name, roots, false)
    if workspace_lock then
      workspace_lock.ensure_instance_lock(config.workspace, name, core.state().instance_id)
    end
    ui.notify(string.format(constants.messages.open_workspace, name))
    sessions.load(name, config.session.enabled, config.session.auto_load)
  end

  function titled.save(name)
    local state = core.state()
    local workspace_name = name ~= "" and name or state.name
    if not workspace_name or workspace_name == "" then
      workspace_name = vim.fn.input(constants.ui.workspace_name_prompt)
    end
    if not workspace_name or workspace_name == "" then
      ui.notify(constants.messages.save_cancelled, vim.log.levels.WARN)
      return
    end
    if not store.is_valid_name(workspace_name) then
      ui.notify(string.format(constants.messages.invalid_workspace_name, workspace_name), vim.log.levels.ERROR)
      return
    end
    if not store.write(workspace_name, state.roots) then
      return
    end
    if state.temporary then
      untitled.release_instance_lock(config.workspace, state.instance_id)
    end
    core.set_workspace(workspace_name, state.roots, false)
    if workspace_lock then
      workspace_lock.ensure_instance_lock(config.workspace, state.name, state.instance_id)
    end
    ui.notify(string.format(constants.messages.saved_workspace, workspace_name))
  end

  function titled.rename(arg1, arg2)
    local state = core.state()
    if arg2 then
      local entry = store.read(arg1)
      if not entry then
        ui.notify(string.format(constants.messages.workspace_not_found, arg1), vim.log.levels.ERROR)
        return
      end
      if not store.is_valid_name(arg2) then
        ui.notify(string.format(constants.messages.invalid_workspace_name, arg2), vim.log.levels.ERROR)
        return
      end
      local from_path = store.path(arg1)
      local to_path = store.path(arg2)
      if vim.fn.filereadable(to_path) == 1 then
        ui.notify(string.format(constants.messages.workspace_exists, arg2), vim.log.levels.ERROR)
        return
      end
      vim.fn.rename(from_path, to_path)
      if state.name == arg1 then
        core.set_workspace(arg2, state.roots, false)
      end
      ui.notify(string.format(constants.messages.renamed_workspace, arg1, arg2))
      return
    end

    if not state.name then
      ui.notify(constants.messages.no_workspace_open, vim.log.levels.ERROR)
      return
    end
    local new_name = arg1
    if not new_name or new_name == "" then
      ui.notify(constants.messages.new_name_required, vim.log.levels.ERROR)
      return
    end
    if not store.is_valid_name(new_name) then
      ui.notify(string.format(constants.messages.invalid_workspace_name, new_name), vim.log.levels.ERROR)
      return
    end
    local current_file = store.path(state.name)
    local target_file = store.path(new_name)
    if current_file and vim.fn.filereadable(current_file) == 1 then
      if vim.fn.filereadable(target_file) == 1 then
        ui.notify(string.format(constants.messages.workspace_exists, new_name), vim.log.levels.ERROR)
        return
      end
      vim.fn.rename(current_file, target_file)
    else
      if not store.write(new_name, state.roots) then
        return
      end
    end
    core.set_workspace(new_name, state.roots, false)
    ui.notify(string.format(constants.messages.renamed_workspace_to, new_name))
  end

  function titled.list_saved()
    return store.list()
  end

  function titled.complete_workspaces(arg_lead)
    return complete_from_list(store.list(), arg_lead)
  end

  function titled.complete_rename(arg_lead, cmd_line)
    return complete_rename(store, arg_lead, cmd_line)
  end

  return titled
end

return M
