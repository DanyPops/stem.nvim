local util = require "tests.test_util"

describe("stem.nvim workspace lock", function()
  local workspace_lock

  before_each(function()
    workspace_lock = require "stem.ws.locks"
    util.reset_by()
  end)

  after_each(function()
    util.flush_by()
  end)

  -- Ensure/release toggles lock presence for a named workspace.
  it("creates and releases named workspace locks", function()
    local config = { temp_root = util.new_temp_dir() }
    util.by("Create a lock for alpha")
    workspace_lock.ensure_instance_lock(config, "alpha", tostring(vim.fn.getpid()))
    assert.is_true(workspace_lock.has_locks(config, "alpha"))

    util.by("Release lock and verify absence")
    workspace_lock.release_instance_lock(config, "alpha", tostring(vim.fn.getpid()))
    assert.is_true(workspace_lock.has_locks(config, "alpha") == false)
  end)

  -- has_other_locks detects locks by other instances.
  it("detects other locks for a workspace", function()
    local config = { temp_root = util.new_temp_dir() }
    util.by("Create two instance locks")
    local current = tostring(vim.fn.getpid())
    workspace_lock.ensure_instance_lock(config, "alpha", current)
    workspace_lock.ensure_instance_lock(config, "alpha", "other-instance")
    assert.is_true(workspace_lock.has_other_locks(config, "alpha", current))
  end)

  -- Stale locks are pruned when checking lock status.
  it("prunes stale lock files", function()
    local config = { temp_root = util.new_temp_dir() }
    local lock_path = workspace_lock.instance_lock_path(config, "alpha", "999999")
    util.by("Write a stale lock file directly")
    vim.fn.mkdir(vim.fn.fnamemodify(lock_path, ":h"), "p")
    vim.fn.writefile({ "stale" }, lock_path)

    util.by("Trigger lock check to prune stale entry")
    assert.is_true(workspace_lock.has_locks(config, "alpha") == false)
    assert.is_true(vim.fn.filereadable(lock_path) == 0)
  end)
end)
