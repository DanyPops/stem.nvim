local constants = require "stem.constants"

local M = {}

-- Coordinator for titled + untitled workspace managers.

local function complete_from_list(list, arg_lead)
  local matches = {}
  for _, item in ipairs(list) do
    if arg_lead == "" or item:find(arg_lead, 1, true) == 1 then
      table.insert(matches, item)
    end
  end
  return matches
end

function M.new(config, deps)
  local core = require("stem.ws.core").new(config, {
    ui = deps.ui,
    mount = deps.mount,
    untitled = deps.untitled,
    workspace_lock = deps.workspace_lock,
    registry = deps.registry,
    events = deps.events,
    lifecycle = require "stem.ws.lifecycle",
    effects = require "stem.ws.effects",
    sessions = deps.sessions,
  })
  local titled = require("stem.ws.titled").new(core, {
    ui = deps.ui,
    store = deps.store,
    sessions = deps.sessions,
    workspace_lock = deps.workspace_lock,
    untitled = deps.untitled,
    config = config,
  })
  local untitled = require("stem.ws.untitled").new(core, {
    ui = deps.ui,
    untitled = deps.untitled,
    config = config,
  })

  local coordinator = {}

  function coordinator.setup()
    core.bootstrap()
  end

  function coordinator.new(name)
    if name and name ~= "" then
      titled.new_named(name)
    else
      untitled.new_untitled()
    end
    local base_dir = core.context_dir()
    if config.workspace.auto_add_cwd and base_dir and base_dir ~= "" and base_dir ~= core.state().temp_root then
      coordinator.add(base_dir)
    end
  end

  function coordinator.open(name)
    titled.open(name)
  end

  function coordinator.save(name)
    titled.save(name)
  end

  function coordinator.close()
    return core.close()
  end

  function coordinator.add(dir)
    core.add(dir)
  end

  function coordinator.remove(dir)
    core.remove(dir)
  end

  function coordinator.rename(arg1, arg2)
    titled.rename(arg1, arg2)
  end

  function coordinator.delete(name)
    titled.delete(name)
  end

  function coordinator.list()
    local untitled_names = untitled.list()
    local saved_names = titled.list_saved()
    if #untitled_names == 0 and #saved_names == 0 then
      deps.ui.notify(constants.messages.no_workspaces)
      return
    end
    local lines = { constants.messages.list_header }
    for _, name in ipairs(untitled_names) do
      local marker = core.state().temp_root and core.state().temp_root:match("/" .. vim.pesc(name) .. "$")
        and constants.ui.list_current_marker or ""
      table.insert(lines, constants.ui.list_item_prefix .. name .. marker)
    end
    for _, name in ipairs(saved_names) do
      local marker = core.state().name == name and constants.ui.list_current_marker or ""
      table.insert(lines, constants.ui.list_item_prefix .. name .. marker)
    end
    deps.ui.notify(table.concat(lines, "\n"))
  end

  function coordinator.status()
    if not core.state().temp_root then
      deps.ui.notify(constants.messages.no_workspace_open)
      return
    end
    local label = core.state().name or constants.names.undefined
    deps.ui.notify(string.format(constants.messages.status_header .. " %s (%d roots)", label, #core.state().roots))
  end

  function coordinator.info(name)
    local label = nil
    local roots = nil
    if not name or name == "" then
      if not core.state().temp_root then
        deps.ui.notify(constants.messages.no_workspace_open)
        return
      end
      label = core.state().name or constants.names.untitled
      roots = core.state().roots
    else
      local entry = deps.store.read(name)
      if entry and type(entry.roots) == "table" then
        label = name
        roots = entry.roots
      else
        local found = nil
        if deps.registry and deps.registry.state then
          for _, ws in pairs(deps.registry.state.workspaces or {}) do
            if ws.temp_root and ws.temp_root:match("/" .. vim.pesc(name) .. "$") then
              found = ws
              break
            end
          end
        end
        if not found then
          deps.ui.notify(string.format(constants.messages.workspace_not_found, name), vim.log.levels.ERROR)
          return
        end
        label = name
        roots = found.roots or {}
      end
    end
    local lines = { constants.messages.status_header .. " " .. label, constants.ui.roots_header }
    if #roots == 0 then
      table.insert(lines, constants.ui.empty_roots_item)
    else
      for _, root in ipairs(roots) do
        table.insert(lines, constants.ui.list_item_prefix .. root)
      end
    end
    deps.ui.notify(table.concat(lines, "\n"))
  end

  function coordinator.complete_workspaces(arg_lead)
    return titled.complete_workspaces(arg_lead)
  end

  function coordinator.complete_roots(arg_lead)
    return core.complete_roots(arg_lead)
  end

  function coordinator.complete_rename(arg_lead, cmd_line)
    return titled.complete_rename(arg_lead, cmd_line)
  end

  function coordinator.complete_info(arg_lead)
    local names = {}
    local seen = {}
    local untitled_names = untitled.list()
    for _, name in ipairs(untitled_names) do
      if not seen[name] then
        table.insert(names, name)
        seen[name] = true
      end
    end
    local saved_names = titled.list_saved()
    for _, name in ipairs(saved_names) do
      if not seen[name] then
        table.insert(names, name)
        seen[name] = true
      end
    end
    return complete_from_list(names, arg_lead)
  end

  function coordinator.state()
    return core.state()
  end

  function coordinator.on_buf_enter(bufnr)
    core.on_buf_enter(bufnr)
  end

  function coordinator.on_buf_leave(bufnr)
    core.on_buf_leave(bufnr)
  end

  coordinator.on_buf_delete = coordinator.on_buf_leave

  return coordinator
end

return M
