local M = {}

local function temp_untitled_root(config)
  local dir = config.temp_untitled_root
  vim.fn.mkdir(dir, "p")
  return dir
end

local function lock_dir(config)
  local dir = temp_untitled_root(config) .. "/.locks"
  vim.fn.mkdir(dir, "p")
  return dir
end

function M.instance_lock_path(config, instance_id)
  return lock_dir(config) .. "/" .. instance_id
end

function M.ensure_instance_lock(config, instance_id)
  vim.fn.writefile({ os.date("!%Y-%m-%dT%H:%M:%SZ") }, M.instance_lock_path(config, instance_id))
end

function M.release_instance_lock(config, instance_id)
  vim.fn.delete(M.instance_lock_path(config, instance_id))
end

function M.next_untitled_name(config)
  local base = temp_untitled_root(config)
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

function M.cleanup_if_last(config)
  local locks = vim.fn.globpath(lock_dir(config), "*", false, true)
  if #locks > 0 then
    return
  end
  local base = temp_untitled_root(config)
  local entries = vim.fn.readdir(base)
  for _, entry in ipairs(entries) do
    if entry ~= ".locks" then
      vim.fn.delete(base .. "/" .. entry, "rf")
    end
  end
end

function M.list(config)
  local base = temp_untitled_root(config)
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

function M.has_locks(config)
  local locks = vim.fn.globpath(lock_dir(config), "*", false, true)
  return #locks > 0
end

function M.temp_root_for(config, name, temporary)
  local base = config.temp_root
  vim.fn.mkdir(base, "p")
  if temporary and (not name or name == "") then
    local temp_base = temp_untitled_root(config)
    return temp_base .. "/" .. M.next_untitled_name(config)
  end
  return base .. "/" .. name
end

return M
