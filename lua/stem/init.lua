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

local ui = require "stem.ui"

local function notify(msg, level)
  ui.notify(msg, level)
end

local function temp_untitled_root()
  local dir = config.workspace.temp_untitled_root
  vim.fn.mkdir(dir, "p")
  return dir
end

local function lock_dir()
  local dir = temp_untitled_root() .. "/.locks"
  vim.fn.mkdir(dir, "p")
  return dir
end

local function instance_lock_path()
  return lock_dir() .. "/" .. state.instance_id
end

local function ensure_instance_lock()
  vim.fn.writefile({ os.date("!%Y-%m-%dT%H:%M:%SZ") }, instance_lock_path())
end

local function release_instance_lock()
  vim.fn.delete(instance_lock_path())
end

local workspace_store = require "stem.workspace_store"

local function list_workspaces()
  return workspace_store.list()
end

local function list_roots()
  local roots = {}
  for _, root in ipairs(state.roots) do
    table.insert(roots, root)
  end
  table.sort(roots)
  return roots
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

local function complete_workspace_names(arg_lead)
  return complete_from_list(list_workspaces(), arg_lead)
end

local function complete_roots(arg_lead)
  return complete_from_list(list_roots(), arg_lead)
end

local function complete_rename(arg_lead, cmd_line)
  local args = vim.split(cmd_line, "%s+")
  if #args <= 2 then
    return complete_workspace_names(arg_lead)
  end
  return {}
end

M._complete = {
  workspaces = complete_workspace_names,
  roots = complete_roots,
  rename = complete_rename,
}

local function next_untitled_name()
  local base = temp_untitled_root()
  local files = vim.fn.globpath(base, "*", false, true)
  local used = {}
  for _, path in ipairs(files) do
    local name = vim.fn.fnamemodify(path, ":t")
    if name:match("^untitled%d*$") then
      used[name] = true
    end
  end
  if not used.untitled then
    return "untitled"
  end
  local i = 1
  while used["untitled" .. i] do
    i = i + 1
  end
  return "untitled" .. i
end

local function temp_root_for(name, temporary)
  local base = config.workspace.temp_root
  vim.fn.mkdir(base, "p")
  if temporary and (not name or name == "") then
    local temp_base = temp_untitled_root()
    return temp_base .. "/" .. next_untitled_name()
  end
  return base .. "/" .. name
end

local function set_cwd(path)
  if not path or path == "" then
    return
  end
  vim.cmd("cd " .. vim.fn.fnameescape(path))
  vim.cmd("tcd " .. vim.fn.fnameescape(path))
end

local function open_root_in_oil()
  if not config.oil.follow then
    return
  end
  if vim.bo.filetype ~= "oil" then
    return
  end
  local ok, oil = pcall(require, "oil")
  if ok then
    pcall(oil.open, state.temp_root)
  end
end

local session_manager = require "stem.session_manager"

local function load_session(name)
  session_manager.load(name, config.session.enabled, config.session.auto_load)
end

local function save_session(name)
  session_manager.save(name, config.session.enabled)
end

local function clear_temp_root(path)
  if not path or path == "" then
    return
  end
  if #state.mounts > 0 then
    for _, mount in ipairs(state.mounts) do
      if vim.fn.isdirectory(mount) == 1 then
        if vim.fn.executable("fusermount") == 1 then
          vim.fn.system { "fusermount", "-u", mount }
        else
          vim.fn.system { "umount", mount }
        end
      end
    end
    state.mounts = {}
  end
  if vim.fn.isdirectory(path) == 0 then
    vim.fn.mkdir(path, "p")
    return
  end
  local entries = vim.fn.readdir(path)
  for _, entry in ipairs(entries) do
    vim.fn.delete(path .. "/" .. entry, "rf")
  end
end

local function cleanup_untitled_if_last()
  local locks = vim.fn.globpath(lock_dir(), "*", false, true)
  if #locks > 0 then
    return
  end
  local base = temp_untitled_root()
  local entries = vim.fn.readdir(base)
  for _, entry in ipairs(entries) do
    if entry ~= ".locks" then
      vim.fn.delete(base .. "/" .. entry, "rf")
    end
  end
end

local function list_untitled()
  local base = temp_untitled_root()
  local names = {}
  local entries = vim.fn.readdir(base)
  for _, entry in ipairs(entries) do
    if entry ~= ".locks" then
      table.insert(names, entry)
    end
  end
  table.sort(names)
  return names
end

local function should_confirm_close()
  if not config.workspace.confirm_close then
    return false
  end
  return #vim.api.nvim_list_uis() > 0
end

local function normalize_dir(path)
  local expanded = vim.fn.expand(path)
  expanded = vim.fn.fnamemodify(expanded, ":p")
  expanded = expanded:gsub("/+$", "")
  return expanded
end

local function mount_roots()
  if not state.temp_root then
    return
  end
  clear_temp_root(state.temp_root)
  state.mount_map = {}
  state.mounts = {}
  local used = {}
  for _, root in ipairs(state.roots) do
    local name = vim.fn.fnamemodify(root, ":t")
    local mount_name = name
    local n = 2
    while used[mount_name] do
      mount_name = string.format("%s__%d", name, n)
      n = n + 1
    end
    used[mount_name] = true
    state.mount_map[root] = mount_name
    local mount_path = state.temp_root .. "/" .. mount_name
    if vim.fn.executable("bindfs") ~= 1 then
      notify("bindfs not found; cannot mount workspace", vim.log.levels.ERROR)
      return
    end
    vim.fn.mkdir(mount_path, "p")
    local cmd = { "bindfs" }
    for _, arg in ipairs(config.workspace.bindfs_args or {}) do
      table.insert(cmd, arg)
    end
    table.insert(cmd, root)
    table.insert(cmd, mount_path)
    local out = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then
      notify(string.format("Failed to bindfs %s: %s", root, out), vim.log.levels.WARN)
    else
      table.insert(state.mounts, mount_path)
    end
  end
end

local function maybe_reopen_in_workspace(root, mount_name)
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  if not name or name == "" then
    return
  end
  local path = normalize_dir(name)
  if path == root then
    local target = state.temp_root .. "/" .. mount_name
    vim.cmd("edit " .. vim.fn.fnameescape(target))
    return
  end
  if path:sub(1, #root + 1) ~= root .. "/" then
    return
  end
  local rel = path:sub(#root + 2)
  local target = state.temp_root .. "/" .. mount_name .. "/" .. rel
  vim.cmd("edit " .. vim.fn.fnameescape(target))
end

local function ensure_workspace()
  if state.temp_root then
    return
  end
  state.temporary = true
  state.temp_root = temp_root_for(state.name, state.temporary)
  mount_roots()
  state.prev_cwd = state.prev_cwd or vim.fn.getcwd()
  set_cwd(state.temp_root)
  open_root_in_oil()
end

local function set_workspace(name, roots, temporary)
  state.name = name
  state.roots = roots or {}
  state.temporary = temporary
  state.temp_root = temp_root_for(name, temporary)
  mount_roots()
  state.prev_cwd = state.prev_cwd or vim.fn.getcwd()
  set_cwd(state.temp_root)
  open_root_in_oil()
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

local function find_root_index(path)
  for i, root in ipairs(state.roots) do
    if root == path then
      return i
    end
  end
  return nil
end

function M.new(name)
  local base_dir = context_dir()
  local workspace_name = name ~= "" and name or nil
  set_workspace(workspace_name, {}, workspace_name == nil)
  if state.temporary then
    ensure_instance_lock()
  end
  if config.workspace.auto_add_cwd and base_dir and base_dir ~= "" and base_dir ~= state.temp_root then
    M.add(base_dir)
  end
  if workspace_name then
    notify("Opened workspace: " .. workspace_name)
    load_session(workspace_name)
  else
    notify "Opened unnamed workspace"
  end
end

function M.open(name)
  if not name or name == "" then
    notify("Workspace name required", vim.log.levels.ERROR)
    return
  end
  local entry = workspace_store.read(name)
  if not entry or type(entry.roots) ~= "table" then
    notify("Workspace not found: " .. name, vim.log.levels.ERROR)
    return
  end
  set_workspace(name, entry.roots, false)
  notify("Opened workspace: " .. name)
  load_session(name)
end

function M.save(name)
  local workspace_name = name ~= "" and name or state.name
  if not workspace_name or workspace_name == "" then
    workspace_name = vim.fn.input "Workspace name: "
  end
  if not workspace_name or workspace_name == "" then
    notify("Save cancelled", vim.log.levels.WARN)
    return
  end
  if not workspace_store.is_valid_name(workspace_name) then
    notify("Invalid workspace name: " .. workspace_name, vim.log.levels.ERROR)
    return
  end
  if not workspace_store.write(workspace_name, state.roots) then
    return
  end
  state.name = workspace_name
  state.temporary = false
  state.temp_root = temp_root_for(state.name, state.temporary)
  mount_roots()
  set_cwd(state.temp_root)
  notify("Saved workspace: " .. workspace_name)
end

function M.close()
  if state.temporary and #state.roots > 0 and should_confirm_close() then
    local choice = ui.confirm("Close unnamed workspace without saving?", "&Yes\n&No", 2)
    if choice ~= 1 then
      return
    end
  end
  if state.name then
    save_session(state.name)
  end
  if state.temporary then
    release_instance_lock()
  end
  if state.temp_root then
    clear_temp_root(state.temp_root)
    vim.fn.delete(state.temp_root, "rf")
  end
  if state.temporary then
    cleanup_untitled_if_last()
  end
  if state.prev_cwd then
    set_cwd(state.prev_cwd)
  end
  state.name = nil
  state.temporary = true
  state.roots = {}
  state.temp_root = nil
  state.prev_cwd = nil
  notify "Workspace closed"
end

function M.add(dir)
  local path = dir and dir ~= "" and normalize_dir(dir) or context_dir()
  if not path or path == "" then
    notify("Directory required", vim.log.levels.ERROR)
    return
  end
  if vim.fn.isdirectory(path) == 0 then
    notify("Not a directory: " .. path, vim.log.levels.ERROR)
    return
  end
  ensure_workspace()
  if find_root_index(path) then
    notify("Already added: " .. path, vim.log.levels.WARN)
    return
  end
  table.insert(state.roots, path)
  mount_roots()
  local mount_name = state.mount_map[path]
  if mount_name then
    maybe_reopen_in_workspace(path, mount_name)
  end
  notify("Added: " .. path)
end

function M.remove(dir)
  if not dir or dir == "" then
    notify("Directory required", vim.log.levels.ERROR)
    return
  end
  if not state.temp_root then
    notify("No workspace open", vim.log.levels.ERROR)
    return
  end
  local path = normalize_dir(dir)
  local idx = find_root_index(path)
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
      notify("Directory not found: " .. dir, vim.log.levels.ERROR)
      return
    end
  end
  table.remove(state.roots, idx)
  mount_roots()
  notify("Removed: " .. path)
end

function M.rename(arg1, arg2)
  if arg2 then
    local entry = workspace_store.read(arg1)
    if not entry then
      notify("Workspace not found: " .. arg1, vim.log.levels.ERROR)
      return
    end
    if not workspace_store.is_valid_name(arg2) then
      notify("Invalid workspace name: " .. arg2, vim.log.levels.ERROR)
      return
    end
    local from_path = workspace_store.path(arg1)
    local to_path = workspace_store.path(arg2)
    if vim.fn.filereadable(to_path) == 1 then
      notify("Workspace already exists: " .. arg2, vim.log.levels.ERROR)
      return
    end
    vim.fn.rename(from_path, to_path)
    if state.name == arg1 then
      state.name = arg2
      state.temporary = false
      state.temp_root = temp_root_for(state.name, state.temporary)
      mount_roots()
      set_cwd(state.temp_root)
    end
    notify(string.format("Renamed workspace: %s -> %s", arg1, arg2))
    return
  end

  if not state.name then
    notify("No workspace open", vim.log.levels.ERROR)
    return
  end
  local new_name = arg1
  if not new_name or new_name == "" then
    notify("New name required", vim.log.levels.ERROR)
    return
  end
  if not workspace_store.is_valid_name(new_name) then
    notify("Invalid workspace name: " .. new_name, vim.log.levels.ERROR)
    return
  end
  local current_file = workspace_store.path(state.name)
  local target_file = workspace_store.path(new_name)
  if current_file and vim.fn.filereadable(current_file) == 1 then
    if vim.fn.filereadable(target_file) == 1 then
      notify("Workspace already exists: " .. new_name, vim.log.levels.ERROR)
      return
    end
    vim.fn.rename(current_file, target_file)
  else
    if not workspace_store.write(new_name, state.roots) then
      return
    end
  end
  state.name = new_name
  state.temporary = false
  state.temp_root = temp_root_for(state.name, state.temporary)
  mount_roots()
  set_cwd(state.temp_root)
  notify("Renamed workspace to: " .. new_name)
end

function M.list()
  local names = list_workspaces()
  if #names == 0 then
    notify "No saved workspaces"
    return
  end
  local lines = { "Workspaces:" }
  for _, name in ipairs(names) do
    local marker = state.name == name and " *" or ""
    table.insert(lines, " - " .. name .. marker)
  end
  notify(table.concat(lines, "\n"))
end

function M.untitled_list()
  local names = list_untitled()
  if #names == 0 then
    notify "No untitled workspaces"
    return
  end
  local lines = { "Untitled workspaces:" }
  for _, name in ipairs(names) do
    local marker = state.temp_root and state.temp_root:match("/" .. vim.pesc(name) .. "$") and " *" or ""
    table.insert(lines, " - " .. name .. marker)
  end
  notify(table.concat(lines, "\n"))
end

function M.status()
  if not state.temp_root then
    notify "No workspace open"
    return
  end
  local label = state.name or "undefined"
  notify(string.format("Workspace: %s (%d roots)", label, #state.roots))
end

local function command_complete_workspaces()
  return list_workspaces()
end

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

  bootstrap()

  vim.api.nvim_create_user_command("StemNew", function(opts)
    M.new(opts.args)
  end, { nargs = "?" })

  vim.api.nvim_create_user_command("StemOpen", function(opts)
    M.open(opts.args)
  end, { nargs = 1, complete = function(arg_lead)
    return complete_workspace_names(arg_lead)
  end })

  vim.api.nvim_create_user_command("StemSave", function(opts)
    M.save(opts.args)
  end, { nargs = "?", complete = function(arg_lead)
    return complete_workspace_names(arg_lead)
  end })

  vim.api.nvim_create_user_command("StemClose", function()
    M.close()
  end, { nargs = 0 })

  vim.api.nvim_create_user_command("StemAdd", function(opts)
    M.add(opts.args)
  end, { nargs = "?", complete = "dir" })

  vim.api.nvim_create_user_command("StemRemove", function(opts)
    M.remove(opts.args)
  end, { nargs = 1, complete = function(arg_lead)
    return complete_roots(arg_lead)
  end })

  vim.api.nvim_create_user_command("StemRename", function(opts)
    local args = vim.split(opts.args, "%s+")
    if #args == 1 then
      M.rename(args[1], nil)
    else
      M.rename(args[1], args[2])
    end
  end, { nargs = "+", complete = function(arg_lead, cmd_line)
    return complete_rename(arg_lead, cmd_line)
  end })

  vim.api.nvim_create_user_command("StemList", function()
    M.list()
  end, { nargs = 0 })

  vim.api.nvim_create_user_command("StemStatus", function()
    M.status()
  end, { nargs = 0 })

  vim.api.nvim_create_user_command("StemUntitledList", function()
    M.untitled_list()
  end, { nargs = 0 })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      if state.temp_root then
        pcall(M.close)
      end
    end,
  })
end

return M
