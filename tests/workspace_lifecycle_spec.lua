local util = require "tests.test_util"

describe("stem.nvim workspace lifecycle", function()
  local stem
  local data_home

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

  -- Setup succeeds only when bindfs and FUSE are available.
  it("bootstraps bindfs and FUSE availability", function()
    util.by("Check bindfs and /dev/fuse availability before setup")
    local has_bindfs = vim.fn.executable("bindfs") == 1
    local has_fuse = vim.fn.filereadable("/dev/fuse") == 1
    util.by("Attempt to run stem.setup")
    local ok, err = pcall(stem.setup, {})
    if has_bindfs and has_fuse then
      assert.is_true(ok)
    else
      assert.is_false(ok)
      assert.is_true(type(err) == "string" and err ~= "")
    end
  end)

  -- Opening an unnamed workspace sets cwd under the untitled temp root.
  it("creates an unnamed workspace with expected cwd", function()
    util.by("Open a new unnamed workspace")
    stem.new("")
    util.by("Verify cwd and temp root")
    local cwd = vim.fn.getcwd()
    local temp_root = vim.env.STEM_TMP_UNTITLED_ROOT or "/tmp/stem/temporary"
    assert.is_true(cwd:match(vim.pesc(temp_root) .. "/untitled$") ~= nil)
    assert.is_true(vim.fn.isdirectory(cwd) == 1)
  end)

  -- Saving then opening a workspace uses the named temp root.
  it("saves and opens a workspace", function()
    util.by("Save a workspace and reopen it")
    local dir = util.new_temp_dir()
    stem.new("")
    util.by("Add directory to workspace")
    stem.add(dir)
    util.by("Save workspace as alpha")
    stem.save("alpha")
    local ws_file = data_home .. "/stem/workspaces/alpha.lua"
    assert.is_true(vim.fn.filereadable(ws_file) == 1)
    util.by("Close workspace before reopening")
    stem.close()
    util.by("Open saved workspace")
    stem.open("alpha")
    local named_root = vim.env.STEM_TMP_ROOT or "/tmp/stem/named"
    util.by("Verify named root cwd")
    assert.is_true(vim.fn.getcwd():match(vim.pesc(named_root) .. "/alpha$") ~= nil)
  end)

  -- Renaming a workspace moves its stored file.
  it("renames a workspace", function()
    util.by("Save and rename a workspace")
    stem.new("")
    util.by("Save workspace as one")
    stem.save("one")
    util.by("Rename workspace to two")
    stem.rename("one", "two")
    local old_file = data_home .. "/stem/workspaces/one.lua"
    local new_file = data_home .. "/stem/workspaces/two.lua"
    util.by("Verify old file removed and new file exists")
    assert.is_true(vim.fn.filereadable(old_file) == 0)
    assert.is_true(vim.fn.filereadable(new_file) == 1)
  end)

  -- Listing and status report include saved workspace names.
  it("lists workspaces and reports status", function()
    util.by("Save a workspace then list and show status")
    local messages, restore = util.capture_notify()
    stem.new("")
    stem.save("listme")
    util.by("List workspaces")
    stem.list()
    util.by("Show workspace status")
    stem.status()
    restore()
    local joined = {}
    for _, item in ipairs(messages) do
      table.insert(joined, item.msg)
    end
    local all = table.concat(joined, "\n")
    util.by("Verify list and status output")
    assert.is_true(all:match("listme") ~= nil)
    assert.is_true(all:match("Workspace:") ~= nil)
  end)
end)
