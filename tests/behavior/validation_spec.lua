local constants = require "stem.constants"
local util = require "tests.test_util"

describe("stem.nvim validation", function()
  local stem
  local data_home

  local function has_message(messages, expected)
    for _, item in ipairs(messages) do
      if item.msg == expected then
        return true
      end
    end
    return false
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

  -- Invalid workspace names are rejected on save.
  it("rejects invalid workspace names on save", function()
    util.by("Attempt to save a workspace with an invalid name")
    local messages, restore = util.capture_notify()
    stem.new("")
    util.by("Save invalid workspace name")
    stem.save("bad/name")
    restore()
    local ws_file = data_home .. "/" .. constants.paths.workspace_dir .. "/bad/name.lua"
    assert.is_true(vim.fn.filereadable(ws_file) == 0)
    local expected = string.format(constants.messages.invalid_workspace_name, "bad/name")
    util.by("Verify invalid name was reported")
    assert.is_true(has_message(messages, expected))
  end)

  -- Opening a missing workspace reports an error.
  it("rejects non-existent workspace on open", function()
    util.by("Attempt to open a missing workspace")
    local messages, restore = util.capture_notify()
    util.by("Open missing workspace")
    stem.open("missing")
    restore()
    local expected = string.format(constants.messages.workspace_not_found, "missing")
    util.by("Verify missing workspace was reported")
    assert.is_true(has_message(messages, expected))
  end)

  -- Adding a non-directory path is rejected.
  it("rejects non-directory on add", function()
    util.by("Attempt to add a non-directory path")
    local dir = util.new_temp_dir()
    local file = util.new_temp_file(dir, "notadir.txt")
    local messages, restore = util.capture_notify()
    stem.new("")
    util.by("Add non-directory path")
    stem.add(file)
    restore()
    local expected = string.format(constants.messages.not_a_directory, file)
    util.by("Verify error was reported")
    assert.is_true(has_message(messages, expected))
  end)

  -- Removing an unknown directory reports an error.
  it("rejects unknown directory on remove", function()
    util.by("Attempt to remove a directory that was never added")
    local dir = util.new_temp_dir()
    local messages, restore = util.capture_notify()
    stem.new("")
    util.by("Remove unknown directory")
    stem.remove(dir)
    restore()
    local expected = string.format(constants.messages.directory_not_found, dir)
    util.by("Verify error was reported")
    assert.is_true(has_message(messages, expected))
  end)

  -- Renaming to an existing workspace name is rejected.
  it("prevents renaming to an existing workspace", function()
    util.by("Create two workspaces and try to rename to existing")
    local messages, restore = util.capture_notify()
    stem.new("")
    util.by("Save workspace one")
    stem.save("one")
    stem.new("")
    util.by("Save workspace two")
    stem.save("two")
    util.by("Attempt to rename one to two")
    stem.rename("one", "two")
    restore()
    local expected = string.format(constants.messages.workspace_exists, "two")
    util.by("Verify rename error was reported")
    assert.is_true(has_message(messages, expected))
  end)
end)
