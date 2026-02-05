local util = require "tests.test_util"

describe("stem.nvim untitled locks", function()
  local untitled

  before_each(function()
    untitled = require "stem.untitled_manager"
    util.reset_by()
  end)

  after_each(function()
    util.flush_by()
  end)

  -- Ensure/release toggles untitled instance locks.
  it("creates and releases untitled instance locks", function()
    local config = { temp_untitled_root = util.new_temp_dir() }
    util.by("Create an untitled instance lock")
    untitled.ensure_instance_lock(config, "inst-1")
    assert.is_true(untitled.has_locks(config))

    util.by("Release lock and verify absence")
    untitled.release_instance_lock(config, "inst-1")
    assert.is_true(untitled.has_locks(config) == false)
  end)

  -- Cleanup removes untitled roots when no locks remain.
  it("cleans untitled roots when no locks exist", function()
    local config = { temp_untitled_root = util.new_temp_dir() }
    local base = config.temp_untitled_root
    util.by("Create untitled roots and clear locks")
    vim.fn.mkdir(base .. "/untitled", "p")
    vim.fn.mkdir(base .. "/untitled1", "p")

    util.by("Run cleanup with no locks")
    untitled.cleanup_if_last(config)

    util.by("Verify untitled roots removed")
    assert.is_true(vim.fn.isdirectory(base .. "/untitled") == 0)
    assert.is_true(vim.fn.isdirectory(base .. "/untitled1") == 0)
  end)
end)
