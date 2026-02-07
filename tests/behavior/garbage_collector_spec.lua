local constants = require "stem.constants"
local gc_helpers = require "stem.gc.helpers"
local util = require "tests.test_util"

describe("stem.nvim garbage collector", function()
  local config
  local mount
  local untitled
  local workspace_lock

  before_each(function()
    util.ensure_bindfs()
    mount = require "stem.mount_manager"
    untitled = require "stem.ws.untitled_store"
    workspace_lock = require "stem.ws.locks"
    local base = util.new_temp_dir()
    config = {
      workspace = {
        temp_root = base .. "/saved",
        temp_untitled_root = base .. "/temp",
      },
    }
  end)

  local function mount_present(target)
    local lines = vim.fn.systemlist({ constants.commands.mount, "-t", constants.mount.fuse_type })
    local targets = gc_helpers.parse_bindfs_mount_targets(lines)
    for _, candidate in ipairs(targets) do
      if candidate == target then
        return true
      end
    end
    return false
  end

  local function mount_roots(temp_root, roots)
    vim.fn.mkdir(temp_root, "p")
    local mounts = mount.mount_roots(roots, temp_root, { "--no-allow-other" })
    return mounts
  end

  local function build_gc()
    return require("stem.gc.collector").new(config, {
      mount = mount,
      untitled = untitled,
      workspace_lock = workspace_lock,
    })
  end

  local function messages_text(messages)
    local joined = {}
    for _, item in ipairs(messages) do
      table.insert(joined, item.msg)
    end
    return table.concat(joined, "\n")
  end

  -- Cleans named mounts when no locks exist.
  it("cleans named mounts without locks", function()
    util.by("Build garbage collector with mount deps")
    local gc = build_gc()

    util.by("Create a named mount with a temp root")
    local roots = { util.new_temp_dir() }
    local temp_root = config.workspace.temp_root .. "/alpha"
    local mounts = mount_roots(temp_root, roots)

    util.by("Verify mount exists before cleanup")
    assert.is_true(#mounts > 0)
    assert.is_true(mount_present(mounts[1]))

    util.by("Run garbage collector")
    gc.collect()

    util.by("Verify mount and temp root removed")
    assert.is_true(mount_present(mounts[1]) == false)
    assert.is_true(vim.fn.isdirectory(temp_root) == 0)
  end)

  -- Keeps named mounts when a live lock exists.
  it("keeps named mounts with live lock", function()
    util.by("Build garbage collector with mount deps")
    local gc = build_gc()

    util.by("Create a named mount and lock it")
    local roots = { util.new_temp_dir() }
    local temp_root = config.workspace.temp_root .. "/alpha"
    local mounts = mount_roots(temp_root, roots)
    workspace_lock.ensure_instance_lock(config.workspace, "alpha", tostring(vim.fn.getpid()))

    util.by("Run garbage collector")
    gc.collect()

    util.by("Verify mount is preserved while lock exists")
    assert.is_true(mount_present(mounts[1]))

    util.by("Release lock and cleanup mount root")
    workspace_lock.release_instance_lock(config.workspace, "alpha", tostring(vim.fn.getpid()))
    mount.unmount_all(mounts)
    vim.fn.delete(temp_root, "rf")
  end)

  -- Cleans untitled mounts when no locks exist.
  it("cleans untitled mounts without locks", function()
    util.by("Build garbage collector with mount deps")
    local gc = build_gc()

    util.by("Create an untitled mount without locks")
    local roots = { util.new_temp_dir() }
    local temp_root = config.workspace.temp_untitled_root .. "/untitled"
    local mounts = mount_roots(temp_root, roots)

    util.by("Run garbage collector")
    gc.collect()

    util.by("Verify untitled mount and root were removed")
    assert.is_true(mount_present(mounts[1]) == false)
    assert.is_true(vim.fn.isdirectory(temp_root) == 0)
  end)

  -- Keeps untitled mounts when a lock exists.
  it("keeps untitled mounts with lock", function()
    util.by("Build garbage collector with mount deps")
    local gc = build_gc()

    util.by("Create an untitled mount and lock it")
    local roots = { util.new_temp_dir() }
    local temp_root = config.workspace.temp_untitled_root .. "/untitled"
    local mounts = mount_roots(temp_root, roots)
    untitled.ensure_instance_lock(config.workspace, "other-instance")

    util.by("Run garbage collector")
    gc.collect()

    util.by("Verify mount is preserved while lock exists")
    assert.is_true(mount_present(mounts[1]))

    util.by("Release lock and cleanup mount root")
    untitled.release_instance_lock(config.workspace, "other-instance")
    mount.unmount_all(mounts)
    vim.fn.delete(temp_root, "rf")
  end)

  -- Cleans untitled mounts under /tmp/nvim.* roots.
  it("cleans untitled mounts under nvim temp roots", function()
    util.by("Build garbage collector with mount deps")
    local gc = build_gc()

    util.by("Create a mount under a /tmp/nvim.* stem-untitled root")
    local user = vim.env.USER or "user"
    local extra_root = string.format("/tmp/nvim.%s/gc-test-%s/0/stem-untitled", user, vim.fn.getpid())
    vim.fn.mkdir(extra_root, "p")
    local roots = { util.new_temp_dir() }
    local temp_root = extra_root .. "/untitled"
    local mounts = mount_roots(temp_root, roots)

    util.by("Run garbage collector")
    gc.collect()

    util.by("Verify extra untitled mount and root were removed")
    assert.is_true(mount_present(mounts[1]) == false)
    assert.is_true(vim.fn.isdirectory(temp_root) == 0)
  end)

  -- Ignores bindfs mounts outside stem roots.
  it("ignores non-stem bindfs mounts", function()
    util.by("Build garbage collector with mount deps")
    local gc = build_gc()

    util.by("Create a bindfs mount outside stem roots")
    local roots = { util.new_temp_dir() }
    local temp_root = util.new_temp_dir() .. "/other"
    local mounts = mount_roots(temp_root, roots)

    util.by("Run garbage collector")
    gc.collect()

    util.by("Verify non-stem mount is untouched")
    assert.is_true(mount_present(mounts[1]))

    util.by("Cleanup test mount")
    mount.unmount_all(mounts)
    vim.fn.delete(temp_root, "rf")
  end)

  -- Reports unmount failures when cleaning.
  it("reports unmount errors", function()
    local gc = build_gc()

    util.by("Create a named mount to clean")
    local roots = { util.new_temp_dir() }
    local temp_root = config.workspace.temp_root .. "/alpha"
    local mounts = mount_roots(temp_root, roots)
    assert.is_true(#mounts > 0)

    util.by("Stub unmount_all to return an error")
    local errors = { { mount = mounts[1], error = "unmount failed" } }
    local orig_unmount_all = mount.unmount_all
    mount.unmount_all = function()
      return errors
    end

    util.by("Capture notifications during cleanup")
    local messages, restore = util.capture_notify()
    gc.collect()
    restore()
    mount.unmount_all = orig_unmount_all

    util.by("Verify unmount error was reported")
    local all = messages_text(messages)
    assert.is_true(all:match("unmount failed") ~= nil)
  end)
end)
