local constants = require "stem.constants"
local util = require "tests.test_util"

describe("stem.nvim workspace locks", function()
  local stem

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

  -- Named workspace stays mounted while another instance holds a lock.
  it("keeps named workspace mounted while another instance holds lock", function()
    util.by("Hold a named lock, close, then release")
    stem.setup({})
    local dir = util.new_temp_dir()
    stem.new("alpha")
    stem.add(dir)
    stem.save("alpha")
    local mount_name = vim.fn.fnamemodify(dir, ":t")
    local mount_path = vim.fn.getcwd() .. "/" .. mount_name

    local locks = require "stem.ws.locks"
    local lock_config = { temp_root = vim.env.STEM_TMP_ROOT or constants.paths.default_temp_root }
    util.by("Acquire another instance lock")
    locks.ensure_instance_lock(lock_config, "alpha", "other-instance")

    util.by("Close workspace while lock exists")
    stem.close()
    assert.is_true(vim.fn.getftype(mount_path) == "dir")

    util.by("Release lock and re-open workspace")
    locks.release_instance_lock(lock_config, "alpha", "other-instance")
    stem.open("alpha")
    stem.close()
    util.by("Verify mount is removed after close")
    assert.is_true(vim.fn.getftype(mount_path) == "")
  end)
end)
