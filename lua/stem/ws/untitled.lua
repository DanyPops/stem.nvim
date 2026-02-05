local constants = require "stem.constants"

local M = {}

-- Manager for untitled (temporary) workspaces.

function M.new(core, deps)
  local ui = deps.ui
  local untitled = deps.untitled
  local config = deps.config

  local manager = {}

  function manager.new_untitled()
    core.set_workspace(nil, {}, true)
    untitled.ensure_instance_lock(config.workspace, core.state().instance_id)
    ui.notify(constants.messages.open_unnamed)
  end

  function manager.list()
    return untitled.list(config.workspace)
  end

  return manager
end

return M
