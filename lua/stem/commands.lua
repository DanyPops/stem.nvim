local constants = require "stem.constants"

local M = {}

-- Command wiring: exposes :Stem* user commands.

-- Register user commands and return completion handlers.
function M.setup(api)
  local complete = {
    workspaces = function(arg_lead)
      return api.complete_workspaces(arg_lead)
    end,
    info = function(arg_lead)
      return api.complete_info(arg_lead)
    end,
    roots = function(arg_lead)
      return api.complete_roots(arg_lead)
    end,
    rename = function(arg_lead, cmd_line)
      return api.complete_rename(arg_lead, cmd_line)
    end,
  }

  vim.api.nvim_create_user_command(constants.user_commands.new, function(opts)
    api.new(opts.args)
  end, { nargs = constants.command_opts.nargs_optional })

  vim.api.nvim_create_user_command(constants.user_commands.open, function(opts)
    api.open(opts.args)
  end, { nargs = constants.command_opts.nargs_required, complete = complete.workspaces })

  vim.api.nvim_create_user_command(constants.user_commands.save, function(opts)
    api.save(opts.args)
  end, { nargs = constants.command_opts.nargs_optional, complete = complete.workspaces })

  vim.api.nvim_create_user_command(constants.user_commands.close, function()
    api.close()
  end, { nargs = constants.command_opts.nargs_none })

  vim.api.nvim_create_user_command(constants.user_commands.delete, function(opts)
    api.delete(opts.args)
  end, { nargs = constants.command_opts.nargs_required, complete = complete.workspaces })

  vim.api.nvim_create_user_command(constants.user_commands.add, function(opts)
    api.add(opts.args)
  end, { nargs = constants.command_opts.nargs_optional, complete = constants.command_opts.complete_dir })

  vim.api.nvim_create_user_command(constants.user_commands.remove, function(opts)
    api.remove(opts.args)
  end, { nargs = constants.command_opts.nargs_required, complete = complete.roots })

  vim.api.nvim_create_user_command(constants.user_commands.rename, function(opts)
    local args = vim.split(opts.args, "%s+")
    if #args == 1 then
      api.rename(args[1], nil)
    else
      api.rename(args[1], args[2])
    end
  end, { nargs = constants.command_opts.nargs_plus, complete = complete.rename })

  vim.api.nvim_create_user_command(constants.user_commands.list, function()
    api.list()
  end, { nargs = constants.command_opts.nargs_none })

  vim.api.nvim_create_user_command(constants.user_commands.status, function()
    api.status()
  end, { nargs = constants.command_opts.nargs_none })

  vim.api.nvim_create_user_command(constants.user_commands.info, function(opts)
    api.info(opts.args)
  end, { nargs = constants.command_opts.nargs_optional, complete = complete.info })

  vim.api.nvim_create_user_command(constants.user_commands.cleanup, function()
    api.cleanup()
  end, { nargs = constants.command_opts.nargs_none })

  return complete
end

return M
