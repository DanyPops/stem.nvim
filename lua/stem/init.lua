local M = {}

local config = {
  workspace = {
    auto_add_cwd = true,
    confirm_close = true,
    temp_root = vim.env.STEM_TMP_ROOT or "/tmp/stem/named",
    temp_untitled_root = vim.env.STEM_TMP_UNTITLED_ROOT or "/tmp/stem/temporary",
    bindfs_args = { "--no-allow-other" },
  },
  session = {
    enabled = true,
    auto_load = true,
  },
  oil = {
    follow = true,
  },
}

local events = require("stem.events").new()
local registry_mod = require "stem.registry"
local registry_state = registry_mod.new()

local manager = require("stem.workspace_manager").new(config, {
  ui = require "stem.ui",
  store = require "stem.workspace_store",
  sessions = require "stem.session_manager",
  mount = require "stem.mount_manager",
  untitled = require "stem.untitled_manager",
  workspace_lock = require "stem.workspace_lock",
  registry = {
    module = registry_mod,
    state = registry_state,
  },
  events = events,
})

local commands = require "stem.commands"

local function setup_autocmds()
  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    callback = function(args)
      manager.on_buf_enter(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWinLeave", "BufDelete" }, {
    callback = function(args)
      manager.on_buf_leave(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      if manager.state().temp_root then
        pcall(manager.close)
      end
    end,
  })
end

M._complete = {
  workspaces = manager.complete_workspaces,
  roots = manager.complete_roots,
  rename = manager.complete_rename,
}

function M.setup(opts)
  if opts and type(opts) == "table" then
    if opts.session then
      config.session = vim.tbl_extend("force", config.session, opts.session)
    end
    if opts.oil then
      config.oil = vim.tbl_extend("force", config.oil, opts.oil)
    end
    if opts.workspace then
      config.workspace = vim.tbl_extend("force", config.workspace, opts.workspace)
    end
  end

  manager.setup()
  M._complete = commands.setup({
    new = manager.new,
    open = manager.open,
    save = manager.save,
    close = manager.close,
    add = manager.add,
    remove = manager.remove,
    rename = manager.rename,
    list = manager.list,
    status = manager.status,
    untitled_list = manager.untitled_list,
    complete_workspaces = manager.complete_workspaces,
    complete_roots = manager.complete_roots,
    complete_rename = manager.complete_rename,
  })
  setup_autocmds()
end

M.new = function(name)
  return manager.new(name)
end
M.open = function(name)
  return manager.open(name)
end
M.save = function(name)
  return manager.save(name)
end
M.close = function()
  return manager.close()
end
M.add = function(dir)
  return manager.add(dir)
end
M.remove = function(dir)
  return manager.remove(dir)
end
M.rename = function(a, b)
  return manager.rename(a, b)
end
M.list = function()
  return manager.list()
end
M.status = function()
  return manager.status()
end
M.untitled_list = function()
  return manager.untitled_list()
end

M.events = events

return M
