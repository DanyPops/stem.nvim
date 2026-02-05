local M = {}

-- Command wiring: exposes :Stem* user commands.

-- Register user commands and return completion handlers.
function M.setup(api)
  local complete = {
    workspaces = function(arg_lead)
      return api.complete_workspaces(arg_lead)
    end,
    roots = function(arg_lead)
      return api.complete_roots(arg_lead)
    end,
    rename = function(arg_lead, cmd_line)
      return api.complete_rename(arg_lead, cmd_line)
    end,
  }

  vim.api.nvim_create_user_command("StemNew", function(opts)
    api.new(opts.args)
  end, { nargs = "?" })

  vim.api.nvim_create_user_command("StemOpen", function(opts)
    api.open(opts.args)
  end, { nargs = 1, complete = complete.workspaces })

  vim.api.nvim_create_user_command("StemSave", function(opts)
    api.save(opts.args)
  end, { nargs = "?", complete = complete.workspaces })

  vim.api.nvim_create_user_command("StemClose", function()
    api.close()
  end, { nargs = 0 })

  vim.api.nvim_create_user_command("StemAdd", function(opts)
    api.add(opts.args)
  end, { nargs = "?", complete = "dir" })

  vim.api.nvim_create_user_command("StemRemove", function(opts)
    api.remove(opts.args)
  end, { nargs = 1, complete = complete.roots })

  vim.api.nvim_create_user_command("StemRename", function(opts)
    local args = vim.split(opts.args, "%s+")
    if #args == 1 then
      api.rename(args[1], nil)
    else
      api.rename(args[1], args[2])
    end
  end, { nargs = "+", complete = complete.rename })

  vim.api.nvim_create_user_command("StemList", function()
    api.list()
  end, { nargs = 0 })

  vim.api.nvim_create_user_command("StemStatus", function()
    api.status()
  end, { nargs = 0 })

  vim.api.nvim_create_user_command("StemUntitledList", function()
    api.untitled_list()
  end, { nargs = 0 })

  return complete
end

return M
