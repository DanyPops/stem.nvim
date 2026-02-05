local util = require "tests.test_util"

describe("stem.nvim mount manager", function()
  local mount

  before_each(function()
    mount = require "stem.mount_manager"
    util.reset_by()
  end)

  after_each(function()
    util.flush_by()
  end)

  -- Clear temp root should refuse paths outside allowed_root.
  it("guards clear_temp_root against unsafe paths", function()
    util.by("Create an allowed root and an unsafe root")
    local allowed_root = util.new_temp_dir()
    local unsafe_root = util.new_temp_dir()
    local unsafe_file = util.new_temp_file(unsafe_root, "keep.txt")

    util.by("Attempt to clear unsafe root with allowed_root guard")
    local _, err = mount.clear_temp_root(unsafe_root, {}, allowed_root)
    assert.is_true(type(err) == "table" and #err > 0)
    assert.is_true(vim.fn.filereadable(unsafe_file) == 1)

    util.by("Clear allowed root contents")
    local child = allowed_root .. "/child"
    vim.fn.mkdir(child, "p")
    local allowed_file = util.new_temp_file(child, "remove.txt")
    local _, err2 = mount.clear_temp_root(child, {}, allowed_root)
    assert.is_true(err2 == nil or #err2 == 0)
    assert.is_true(vim.fn.filereadable(allowed_file) == 0)
  end)

  -- Mount roots should return an error when bindfs is missing.
  it("reports missing bindfs as an error", function()
    util.by("Stub bindfs executable to missing")
    local orig = vim.fn.executable
    vim.fn.executable = function(cmd)
      if cmd == "bindfs" then
        return 0
      end
      return orig(cmd)
    end

    local temp_root = util.new_temp_dir()
    local roots = { util.new_temp_dir() }
    local _, _, errors = mount.mount_roots(roots, temp_root, {})

    vim.fn.executable = orig

    util.by("Verify errors list includes bindfs missing")
    assert.is_true(type(errors) == "table")
    assert.is_true(#errors > 0)
  end)

  -- Unmount failures should be surfaced as errors.
  it("returns errors when unmount fails", function()
    util.by("Create a fake mount path")
    local mount_path = util.new_temp_dir()

    util.by("Force umount usage and attempt unmount")
    local orig_executable = vim.fn.executable
    vim.fn.executable = function(cmd)
      if cmd == "fusermount" then
        return 1
      end
      return orig_executable(cmd)
    end

    local errors = mount.unmount_all({ mount_path })

    vim.fn.executable = orig_executable

    util.by("Verify errors list is returned")
    assert.is_true(type(errors) == "table")
    assert.is_true(#errors == 1)
  end)
end)
