local constants = require "stem.constants"
local util = require "tests.test_util"

describe("stem.nvim sessions", function()
  local stem
  local data_home

  local function session_path(name)
    return data_home .. "/" .. constants.paths.session_dir .. "/" .. name .. ".vim"
  end

  before_each(function()
    data_home = vim.fn.stdpath "data"
    util.ensure_bindfs()
    stem = util.reset_stem()
    util.reset_editor()
    util.reset_by()
    local temp_cwd = util.new_temp_dir()
    vim.cmd("cd " .. vim.fn.fnameescape(temp_cwd))
    vim.cmd("tcd " .. vim.fn.fnameescape(temp_cwd))
  end)

  after_each(function()
    pcall(stem.close)
    util.flush_by()
  end)

  -- Named workspaces write sessions that can be loaded later.
  it("writes and loads sessions for named workspaces", function()
    util.by("Create a session and verify it loads")
    local dir = util.new_temp_dir()
    local file = util.new_temp_file(dir, "file.txt")
    stem.new("sess")
    util.by("Open a file in the workspace")
    vim.cmd("edit " .. vim.fn.fnameescape(file))
    util.by("Save workspace to persist session")
    stem.save("sess")
    stem.close()
    util.by("Verify session file exists")
    assert.is_true(vim.fn.filereadable(session_path("sess")) == 1)
    util.by("Open saved workspace to load session")
    stem.open("sess")
    assert.is_true(vim.fn.filereadable(session_path("sess")) == 1)
  end)

  -- Session load does not abandon a modified buffer.
  it("does not abandon modified buffers during session load", function()
    util.by("Create a dirty buffer then open a workspace")
    local dir = util.new_temp_dir()
    local file = util.new_temp_file(dir, "conflict.txt")
    stem.new("conflict")
    util.by("Open a file and save workspace")
    vim.cmd("edit " .. vim.fn.fnameescape(file))
    stem.save("conflict")
    stem.close()

    util.by("Create a modified buffer")
    local prev_hidden = vim.o.hidden
    vim.o.hidden = false
    vim.cmd "enew"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "dirty" })
    vim.bo.modified = true

    util.by("Open workspace and verify buffer stays modified")
    stem.open("conflict")
    assert.is_true(vim.bo.modified == true)
    vim.o.hidden = prev_hidden
  end)
end)
