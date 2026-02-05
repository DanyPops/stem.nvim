local M = {}

-- Plugin entrypoint: builds core services and exposes public API.

local constants = require "stem.constants"

local config = {
  workspace = {
    auto_add_cwd = true,
    confirm_close = true,
    temp_root = vim.env[constants.env.tmp_root] or constants.paths.default_temp_root,
    temp_untitled_root = vim.env[constants.env.tmp_untitled_root] or constants.paths.default_temp_untitled_root,
    bindfs_args = vim.deepcopy(constants.bindfs.default_args),
  },
  session = {
    enabled = true,
    auto_load = true,
  },
  oil = {
    enabled = true,
    follow = true,
  },
}

local events = require("stem.events").new()
local registry_mod = require "stem.registry"
local registry_state = registry_mod.new()
local garbage_collector = require("stem.garbage_collector").new(config, {
  registry = {
    module = registry_mod,
    state = registry_state,
  },
  mount = require "stem.mount_manager",
  untitled = require "stem.untitled_manager",
  workspace_lock = require "stem.workspace_lock",
})

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

-- Autocmds keep buffer tracking and cleanup in sync.
local function setup_autocmds()
  vim.api.nvim_create_autocmd(constants.autocmds.buf_enter, {
    callback = function(args)
      manager.on_buf_enter(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd(constants.autocmds.buf_leave, {
    callback = function(args)
      manager.on_buf_leave(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd(constants.autocmds.vim_leave_pre, {
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

-- Configure stem and register commands/autocmds.
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
  garbage_collector.collect()
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
    info = manager.info,
    cleanup = garbage_collector.collect,
    complete_workspaces = manager.complete_workspaces,
    complete_roots = manager.complete_roots,
    complete_rename = manager.complete_rename,
    complete_info = manager.complete_info,
  })
  setup_autocmds()
end

-- Start a new workspace.
M.new = function(name)
  return manager.new(name)
end
-- Open a saved workspace by name.
M.open = function(name)
  return manager.open(name)
end
-- Save current workspace, optionally as name.
M.save = function(name)
  return manager.save(name)
end
-- Close current workspace and cleanup.
M.close = function()
  return manager.close()
end
-- Add a root directory to the workspace.
M.add = function(dir)
  return manager.add(dir)
end
-- Remove a root directory from the workspace.
M.remove = function(dir)
  return manager.remove(dir)
end
-- Rename current or saved workspace.
M.rename = function(a, b)
  return manager.rename(a, b)
end
-- List saved workspaces.
M.list = function()
  return manager.list()
end
-- Report current workspace status.
M.status = function()
  return manager.status()
end
-- Show roots for current or saved workspace.
M.info = function(name)
  return manager.info(name)
end
-- Cleanup orphaned workspace mounts.
M.cleanup = function()
  return garbage_collector.collect()
end

M.events = events

return M
