local util = require "tests.test_util"

describe("stem.nvim completions", function()
  local stem

  local function assert_contains(items, expected)
    assert.is_true(vim.tbl_contains(items, expected))
  end

  before_each(function()
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

  -- StemOpen completion includes saved workspace names.
  it("completes StemOpen from saved workspaces", function()
    util.by("Save a workspace then complete StemOpen")
    stem.new("")
    util.by("Save workspace alpha")
    stem.save("alpha")
    util.by("Request completion list")
    local items = stem._complete.workspaces("a")
    util.by("Verify completion includes alpha")
    assert_contains(items, "alpha")
  end)

  -- StemSave completion includes saved workspace names.
  it("completes StemSave from saved workspaces", function()
    util.by("Save a workspace then complete StemSave")
    stem.new("")
    util.by("Save workspace bravo")
    stem.save("bravo")
    util.by("Request completion list")
    local items = stem._complete.workspaces("b")
    util.by("Verify completion includes bravo")
    assert_contains(items, "bravo")
  end)

  -- StemRemove completion includes current roots.
  it("completes StemRemove from current roots", function()
    util.by("Add a root then complete StemRemove")
    stem.new("")
    local dir = util.new_temp_dir()
    util.by("Add directory to workspace")
    stem.add(dir)
    util.by("Request completion list")
    local items = stem._complete.roots(dir:sub(1, 3))
    util.by("Verify completion includes directory")
    assert_contains(items, dir)
  end)

  -- StemRename completion suggests existing workspace names.
  it("completes StemRename first arg from workspaces", function()
    util.by("Save a workspace then complete StemRename")
    stem.new("")
    util.by("Save workspace charlie")
    stem.save("charlie")
    util.by("Request completion list")
    local items = stem._complete.rename("c", "StemRename c")
    util.by("Verify completion includes charlie")
    assert_contains(items, "charlie")
  end)
end)
