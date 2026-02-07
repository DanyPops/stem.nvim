local constants = require "stem.constants"
local util = require "tests.test_util"

describe("stem.nvim untitled workspaces", function()
  local stem

  local function untitled_root()
    return vim.env.STEM_TMP_UNTITLED_ROOT or constants.paths.default_temp_untitled_root
  end

  local function mount_path_for(dir)
    local mount_name = vim.fn.fnamemodify(dir, ":t")
    return vim.fn.getcwd() .. "/" .. mount_name
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

  -- Closing the last instance cleans up untitled directories.
  it("clears all untitled workspaces when last instance closes", function()
    util.by("Close last instance and verify cleanup")
    stem.new("")
    local base = untitled_root()
    local extra = base .. "/untitled1"
    util.by("Create extra untitled directory")
    vim.fn.mkdir(extra, "p")
    util.by("Close workspace to trigger cleanup")
    stem.close()
    util.by("Wait for cleanup to complete")
    local cleaned = vim.wait(1000, function()
      local remaining = vim.fn.readdir(base)
      for _, entry in ipairs(remaining) do
        if entry ~= ".locks" then
          return false
        end
      end
      return true
    end, 50)
    assert.is_true(cleaned)
    local remaining = vim.fn.readdir(base)
    local has_dirs = false
    for _, entry in ipairs(remaining) do
      if entry ~= ".locks" then
        has_dirs = true
      end
    end
    util.by("Verify untitled directories removed")
    assert.is_true(has_dirs == false)
  end)

  -- Untitled directories remain when another instance lock exists.
  it("keeps other untitled workspaces when another instance is active", function()
    util.by("Create a lock file and close the workspace")
    stem.new("")
    local base = untitled_root()
    local other = base .. "/untitled1"
    util.by("Create another untitled workspace directory")
    vim.fn.mkdir(other, "p")
    local lock_dir = base .. "/.locks"
    vim.fn.mkdir(lock_dir, "p")
    util.by("Write another instance lock")
    vim.fn.writefile({ "other" }, lock_dir .. "/other-instance")
    util.by("Close workspace and ensure other stays")
    stem.close()
    assert.is_true(vim.fn.isdirectory(other) == 1)
  end)

  -- Mount stays when an untitled lock exists.
  it("does not unmount when untitled locks exist", function()
    util.by("Hold an untitled lock and close the buffer")
    stem.setup({})
    stem.new("")
    local base = untitled_root()
    local lock_dir = base .. "/.locks"
    vim.fn.mkdir(lock_dir, "p")
    util.by("Create untitled lock file")
    vim.fn.writefile({ "other" }, lock_dir .. "/other-instance")
    local dir = util.new_temp_dir()
    local file = util.new_temp_file(dir, "lock.txt")
    stem.add(dir)
    local mount_path = mount_path_for(dir)
    util.by("Open buffer within mounted path")
    vim.cmd("edit! " .. vim.fn.fnameescape(mount_path .. "/lock.txt"))
    local buf = vim.api.nvim_get_current_buf()
    util.by("Close buffer while lock exists")
    vim.api.nvim_buf_delete(buf, { force = true })
    util.by("Verify mount still exists")
    assert.is_true(vim.fn.getftype(mount_path) == "dir")
  end)
end)
