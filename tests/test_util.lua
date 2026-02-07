local constants = require "stem.constants"
local gc_helpers = require "stem.gc.helpers"

local M = {}

local function color(code, text)
  return string.format("\27[%sm%s\27[0m", code, text)
end

local colors = {
  by = 33,
  note = 93,
}

local function time_tag()
  local sec, usec = vim.loop.gettimeofday()
  local ms = math.floor(usec / 1000)
  return os.date("%H:%M:%S", sec) .. "." .. string.format("%03d", ms)
end

local function time_prefix()
  return "[" .. time_tag() .. "] "
end

local function print_labeled(indent, label, color_code, msg)
  local raw_label = indent .. label .. " "
  local prefix = time_prefix() .. indent .. color(color_code, label) .. " "
  local cont_prefix = time_prefix() .. string.rep(" ", #raw_label)
  local lines = vim.split(tostring(msg), "\n", { plain = true })
  if #lines == 0 then
    print(prefix)
    return
  end
  for i, line in ipairs(lines) do
    if i == 1 then
      print(prefix .. line)
    else
      print(cont_prefix .. line)
    end
  end
end
local by_messages = {}
local notify_listeners = {}
local notify_installed = false
local notify_passthrough = nil
local current_test = nil
local current_test_messages = {}

-- Test helpers for temp files, reset, and step logging.

M.new_temp_dir = function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return dir
end

M.new_temp_file = function(dir, name)
  local path = dir .. "/" .. name
  vim.fn.writefile({ "content" }, path)
  return path
end

M.reset_stem = function()
  local info = debug.getinfo(1, "S")
  local source = info and info.source or ""
  if source:sub(1, 1) == "@" then
    local path = source:sub(2)
    local root = vim.fn.fnamemodify(path, ":h:h")
    if root and root ~= "" then
      vim.opt.rtp:prepend(root)
      local lua_root = root .. "/lua"
      if not package.path:find(lua_root, 1, true) then
        package.path = package.path
          .. ";" .. lua_root .. "/?.lua"
          .. ";" .. lua_root .. "/?/init.lua"
      end
    end
  end
  package.loaded.stem = nil
  return require "stem"
end

M.capture_notify = function()
  local messages = {}
  local remove = M.add_notify_listener(function(msg, level, opts)
    table.insert(messages, { msg = msg, level = level, opts = opts })
  end)
  return messages, remove
end

M.add_notify_listener = function(fn)
  table.insert(notify_listeners, fn)
  return function()
    for i, cb in ipairs(notify_listeners) do
      if cb == fn then
        table.remove(notify_listeners, i)
        break
      end
    end
  end
end

M.install_notify_capture = function(disable_passthrough)
  if notify_installed then
    return
  end
  notify_installed = true
  notify_passthrough = vim.notify
  vim.notify = function(msg, level, opts)
    for _, cb in ipairs(notify_listeners) do
      pcall(cb, msg, level, opts)
    end
  if current_test then
    print_labeled("  ", "[Note]", colors.note, msg)
    end
    if not disable_passthrough and notify_passthrough then
      return notify_passthrough(msg, level, opts)
    end
  end
end

M.ensure_bindfs = function()
  if vim.fn.executable(constants.commands.bindfs) ~= 1 or vim.fn.filereadable("/dev/fuse") == 0 then
    error("bindfs and /dev/fuse are required for tests")
  end
end

M.cleanup_test_mounts = function()
  local cmd = { constants.commands.mount, "-t", constants.mount.fuse_type }
  local lines = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    error("Failed to list bindfs mounts")
  end
  local targets = gc_helpers.parse_bindfs_mount_targets(lines)
  local roots = gc_helpers.detect_untitled_roots(targets)
  local filtered_targets = {}
  for _, target in ipairs(targets) do
    if target:match("^/tmp/nvim%.[^/]+/0/stem%-untitled/") then
      table.insert(filtered_targets, target)
    end
  end
  if #filtered_targets == 0 then
    return
  end
  local unmount = vim.fn.executable(constants.commands.fusermount) == 1
      and { constants.commands.fusermount, "-u" }
    or { constants.commands.umount }
  for _, target in ipairs(filtered_targets) do
    local result = vim.fn.systemlist(vim.list_extend(vim.deepcopy(unmount), { target }))
    if vim.v.shell_error ~= 0 then
      error(string.format("Failed to unmount %s: %s", target, table.concat(result, "\n")))
    end
  end

  for root in pairs(roots) do
    if vim.fn.isdirectory(root) == 1 then
      local lock_dir = root .. "/" .. constants.names.locks_dir
      if not gc_helpers.has_live_locks(lock_dir) then
        local entries = vim.fn.readdir(root)
        for _, entry in ipairs(entries) do
          if entry ~= constants.names.locks_dir then
            vim.fn.delete(root .. "/" .. entry, "rf")
          end
        end
      end
    end
  end
end

M.reset_editor = function()
  local prev_hidden = vim.o.hidden
  vim.o.hidden = true
  vim.cmd("silent! tabonly!")
  local wins = vim.api.nvim_tabpage_list_wins(0)
  for i = #wins, 2, -1 do
    vim.api.nvim_win_close(wins[i], true)
  end
  local scratch = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, scratch)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if bufnr ~= scratch then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end
  vim.o.hidden = prev_hidden
end

M.reset_by = function()
  by_messages = {}
end

M.assert_temp_root_clean = function()
  M.cleanup_test_mounts()
  local data_home = vim.env.XDG_DATA_HOME
  if data_home and data_home ~= "" and vim.fn.isdirectory(data_home) == 1 then
    vim.fn.delete(data_home, "rf")
  end
  local test_root = "/tmp/stem.nvim.test"
  if vim.fn.isdirectory(test_root) == 1 then
    vim.fn.delete(test_root, "rf")
  end
  local parent = vim.g.stem_test_tmp_parent
  local before = vim.g.stem_test_tmp_entries or {}
  if not parent or parent == "" or vim.fn.isdirectory(parent) == 0 then
    return
  end
  local after = vim.fn.readdir(parent)
  table.sort(before)
  table.sort(after)
  if #before ~= #after then
    error("Temp root mismatch after tests")
  end
  for i, entry in ipairs(before) do
    if after[i] ~= entry then
      error("Temp root mismatch after tests")
    end
  end

end

M.by = function(msg)
  if current_test then
    print_labeled("  ", "[By]", colors.by, msg)
    return
  end
  table.insert(by_messages, msg)
end

M.flush_by = function()
  for _, msg in ipairs(by_messages) do
    print_labeled("  ", "[By]", colors.by, msg)
  end
  by_messages = {}
end

M.set_current_test = function(name)
  current_test = name
  current_test_messages[current_test] = current_test_messages[current_test] or {}
end

M.flush_current_test = function()
  if not current_test then
    return
  end
  local messages = current_test_messages[current_test] or {}
  for _, msg in ipairs(messages) do
    print_labeled("  ", "[Note]", colors.note, msg)
  end
  current_test_messages[current_test] = {}
end

M.clear_current_test = function()
  current_test = nil
end

return M
