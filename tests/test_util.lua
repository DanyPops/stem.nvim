local constants = require "stem.constants"
local gc_helpers = require "stem.gc.helpers"

local M = {}
local by_messages = {}

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
  local orig = vim.notify
  vim.notify = function(msg, level, opts)
    table.insert(messages, { msg = msg, level = level, opts = opts })
  end
  return messages, function()
    vim.notify = orig
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

M.by = function(msg)
  table.insert(by_messages, msg)
end

M.flush_by = function()
  for _, msg in ipairs(by_messages) do
    vim.notify(("By: %s"):format(msg))
  end
  by_messages = {}
end

return M
