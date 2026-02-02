local M = {}

local state = {
  name = nil,
  temporary = true,
  roots = {},
  temp_root = nil,
  prev_cwd = nil,
}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "stem" })
end

local function workspace_dir()
  local dir = vim.fn.stdpath "data" .. "/stem/workspaces"
  vim.fn.mkdir(dir, "p")
  return dir
end

local function is_valid_name(name)
  return name and name ~= "" and name:match("^[%w%._%-]+$")
end

local function workspace_file(name)
  if not is_valid_name(name) then
    return nil
  end
  return workspace_dir() .. "/" .. name .. ".lua"
end

local function read_workspace(name)
  local path = workspace_file(name)
  if not path or vim.fn.filereadable(path) == 0 then
    return nil
  end
  local chunk, err = loadfile(path)
  if not chunk then
    notify(string.format("Failed to load workspace %s: %s", name, err or "unknown error"), vim.log.levels.WARN)
    return nil
  end
  if setfenv then
    setfenv(chunk, {})
  end
  local ok, result = pcall(chunk)
  if not ok or type(result) ~= "table" then
    return nil
  end
  return result
end

local function write_workspace(name, roots)
  local path = workspace_file(name)
  if not path then
    notify("Invalid workspace name: " .. tostring(name), vim.log.levels.ERROR)
    return false
  end
  local encoded = "return " .. vim.inspect({ roots = roots })
  vim.fn.writefile(vim.split(encoded, "\n"), path)
  return true
end

local function list_workspaces()
  local dir = workspace_dir()
  local files = vim.fn.globpath(dir, "*.lua", false, true)
  local names = {}
  for _, file in ipairs(files) do
    local name = vim.fn.fnamemodify(file, ":t:r")
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

local function temp_root_for(name, temporary)
  local base = "/tmp/stem"
  vim.fn.mkdir(base, "p")
  if temporary and (not name or name == "") then
    return base .. "/undefined"
  end
  return base .. "/" .. name
end

local function clear_temp_root(path)
  if not path or path == "" then
    return
  end
  vim.fn.delete(path, "rf")
  vim.fn.mkdir(path, "p")
end

local function link_roots()
  if not state.temp_root then
    return
  end
  clear_temp_root(state.temp_root)
  local used = {}
  for _, root in ipairs(state.roots) do
    local name = vim.fn.fnamemodify(root, ":t")
    local link_name = name
    local n = 2
    while used[link_name] do
      link_name = string.format("%s__%d", name, n)
      n = n + 1
    end
    used[link_name] = true
    local link_path = state.temp_root .. "/" .. link_name
    local ok, err = (vim.uv or vim.loop).fs_symlink(root, link_path)
    if not ok then
      notify(string.format("Failed to link %s: %s", root, err or "unknown error"), vim.log.levels.WARN)
    end
  end
end

local function ensure_workspace()
  if state.temp_root then
    return
  end
  state.temporary = true
  state.temp_root = temp_root_for(state.name, state.temporary)
  link_roots()
  state.prev_cwd = state.prev_cwd or vim.fn.getcwd()
  vim.fn.chdir(state.temp_root)
end

local function set_workspace(name, roots, temporary)
  state.name = name
  state.roots = roots or {}
  state.temporary = temporary
  state.temp_root = temp_root_for(name, temporary)
  link_roots()
  state.prev_cwd = state.prev_cwd or vim.fn.getcwd()
  vim.fn.chdir(state.temp_root)
end

local function normalize_dir(path)
  local expanded = vim.fn.expand(path)
  expanded = vim.fn.fnamemodify(expanded, ":p")
  expanded = expanded:gsub("/+$", "")
  return expanded
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
  local workspace_name = name ~= "" and name or nil
  set_workspace(workspace_name, {}, workspace_name == nil)
  if workspace_name then
    notify("Opened workspace: " .. workspace_name)
  else
    notify "Opened unnamed workspace"
  end
end

function M.open(name)
  if not name or name == "" then
    notify("Workspace name required", vim.log.levels.ERROR)
    return
  end
  local entry = read_workspace(name)
  if not entry or type(entry.roots) ~= "table" then
    notify("Workspace not found: " .. name, vim.log.levels.ERROR)
    return
  end
  set_workspace(name, entry.roots, false)
  notify("Opened workspace: " .. name)
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
  if not is_valid_name(workspace_name) then
    notify("Invalid workspace name: " .. workspace_name, vim.log.levels.ERROR)
    return
  end
  if not write_workspace(workspace_name, state.roots) then
    return
  end
  state.name = workspace_name
  state.temporary = false
  state.temp_root = temp_root_for(state.name, state.temporary)
  link_roots()
  vim.fn.chdir(state.temp_root)
  notify("Saved workspace: " .. workspace_name)
end

function M.close()
  if state.temporary and #state.roots > 0 then
    local choice = vim.fn.confirm("Close unnamed workspace without saving?", "&Yes\n&No", 2)
    if choice ~= 1 then
      return
    end
  end
  if state.temp_root then
    vim.fn.delete(state.temp_root, "rf")
  end
  if state.prev_cwd then
    vim.fn.chdir(state.prev_cwd)
  end
  state.name = nil
  state.temporary = true
  state.roots = {}
  state.temp_root = nil
  state.prev_cwd = nil
  notify "Workspace closed"
end

function M.add(dir)
  if not dir or dir == "" then
    notify("Directory required", vim.log.levels.ERROR)
    return
  end
  local path = normalize_dir(dir)
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
  link_roots()
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
  link_roots()
  notify("Removed: " .. path)
end

function M.rename(arg1, arg2)
  if arg2 then
    local entry = read_workspace(arg1)
    if not entry then
      notify("Workspace not found: " .. arg1, vim.log.levels.ERROR)
      return
    end
    if not is_valid_name(arg2) then
      notify("Invalid workspace name: " .. arg2, vim.log.levels.ERROR)
      return
    end
    local from_path = workspace_file(arg1)
    local to_path = workspace_file(arg2)
    if vim.fn.filereadable(to_path) == 1 then
      notify("Workspace already exists: " .. arg2, vim.log.levels.ERROR)
      return
    end
    vim.fn.rename(from_path, to_path)
    if state.name == arg1 then
      state.name = arg2
      state.temporary = false
      state.temp_root = temp_root_for(state.name, state.temporary)
      link_roots()
      vim.fn.chdir(state.temp_root)
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
  if not is_valid_name(new_name) then
    notify("Invalid workspace name: " .. new_name, vim.log.levels.ERROR)
    return
  end
  local current_file = workspace_file(state.name)
  local target_file = workspace_file(new_name)
  if current_file and vim.fn.filereadable(current_file) == 1 then
    if vim.fn.filereadable(target_file) == 1 then
      notify("Workspace already exists: " .. new_name, vim.log.levels.ERROR)
      return
    end
    vim.fn.rename(current_file, target_file)
  else
    if not write_workspace(new_name, state.roots) then
      return
    end
  end
  state.name = new_name
  state.temporary = false
  state.temp_root = temp_root_for(state.name, state.temporary)
  link_roots()
  vim.fn.chdir(state.temp_root)
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

function M.setup()
  vim.api.nvim_create_user_command("StemNew", function(opts)
    M.new(opts.args)
  end, { nargs = "?" })

  vim.api.nvim_create_user_command("StemOpen", function(opts)
    M.open(opts.args)
  end, { nargs = 1, complete = command_complete_workspaces })

  vim.api.nvim_create_user_command("StemSave", function(opts)
    M.save(opts.args)
  end, { nargs = "?" })

  vim.api.nvim_create_user_command("StemClose", function()
    M.close()
  end, { nargs = 0 })

  vim.api.nvim_create_user_command("StemAdd", function(opts)
    M.add(opts.args)
  end, { nargs = 1, complete = "dir" })

  vim.api.nvim_create_user_command("StemRemove", function(opts)
    M.remove(opts.args)
  end, { nargs = 1, complete = "dir" })

  vim.api.nvim_create_user_command("StemRename", function(opts)
    local args = vim.split(opts.args, "%s+")
    if #args == 1 then
      M.rename(args[1], nil)
    else
      M.rename(args[1], args[2])
    end
  end, { nargs = "+" })

  vim.api.nvim_create_user_command("StemList", function()
    M.list()
  end, { nargs = 0 })

  vim.api.nvim_create_user_command("StemStatus", function()
    M.status()
  end, { nargs = 0 })
end

return M
