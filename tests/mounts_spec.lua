local util = require "tests.test_util"

describe("stem.nvim mounts", function()
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

  -- Adding a directory creates a mount and removing it tears the mount down.
  it("adds and removes directories", function()
    util.by("Add then remove a workspace root")
    stem.new("")
    local dir = util.new_temp_dir()
    util.by("Add directory to workspace")
    stem.add(dir)
    local mount_name = vim.fn.fnamemodify(dir, ":t")
    local mount_path = vim.fn.getcwd() .. "/" .. mount_name
    assert.is_true(vim.fn.getftype(mount_path) == "dir")
    util.by("Remove directory from workspace")
    stem.remove(dir)
    assert.is_true(vim.fn.getftype(mount_path) == "")
  end)

  -- Adding a directory creates a bindfs-backed mount.
  it("bindfs-backed mount is created successfully", function()
    util.by("Mount a directory via bindfs")
    stem.new("")
    local dir = util.new_temp_dir()
    util.by("Add directory to workspace")
    stem.add(dir)
    local mount_name = vim.fn.fnamemodify(dir, ":t")
    local mount_path = vim.fn.getcwd() .. "/" .. mount_name
    util.by("Verify mount exists")
    assert.is_true(vim.fn.getftype(mount_path) == "dir")
  end)

  -- Adding a relative path works from a changed cwd.
  it("accepts relative paths for StemAdd", function()
    util.by("Change cwd and add a relative path")
    local base = util.new_temp_dir()
    local rel = base .. "/relrepo"
    vim.fn.mkdir(rel, "p")
    stem.new("")
    local temp_root = vim.fn.getcwd()
    util.by("Switch cwd to base")
    vim.cmd("cd " .. vim.fn.fnameescape(base))
    vim.cmd("tcd " .. vim.fn.fnameescape(base))
    util.by("Add relative path")
    stem.add("relrepo")
    util.by("Restore original cwd")
    vim.cmd("cd " .. vim.fn.fnameescape(temp_root))
    vim.cmd("tcd " .. vim.fn.fnameescape(temp_root))
    local mount_path = temp_root .. "/relrepo"
    util.by("Verify relative mount exists")
    assert.is_true(vim.fn.getftype(mount_path) == "dir")
  end)

  -- Bindfs mount failures are reported via notify.
  it("reports bindfs mount failures", function()
    util.by("Use invalid bindfs args and add a directory")
    local messages, restore = util.capture_notify()
    util.by("Configure invalid bindfs args")
    stem.setup({ workspace = { bindfs_args = { "--not-a-real-flag" } } })
    stem.new("")
    local dir = util.new_temp_dir()
    util.by("Add directory to trigger bindfs failure")
    stem.add(dir)
    restore()
    local saw_failure = false
    for _, item in ipairs(messages) do
      if item.msg:match("Failed to bindfs") then
        saw_failure = true
      end
    end
    util.by("Verify failure was reported")
    assert.is_true(saw_failure)
  end)

  -- Duplicate base names are disambiguated when mounting.
  it("disambiguates duplicate root names when mounting", function()
    util.by("Add two directories with the same base name")
    local base = util.new_temp_dir()
    local repo1 = base .. "/repo"
    local repo2 = base .. "/other/repo"
    vim.fn.mkdir(repo1, "p")
    vim.fn.mkdir(repo2, "p")
    stem.new("")
    util.by("Add first repo")
    stem.add(repo1)
    util.by("Add second repo")
    stem.add(repo2)
    local cwd = vim.fn.getcwd()
    util.by("Verify both mounts exist with disambiguation")
    assert.is_true(vim.fn.getftype(cwd .. "/repo") == "dir")
    assert.is_true(vim.fn.getftype(cwd .. "/repo__2") == "dir")
  end)

  -- Mount unmounts when the last buffer from it closes.
  it("tracks buffers and unmounts when last buffer closes", function()
    util.by("Open a buffer in a mount and close it")
    stem.setup({})
    stem.new("alpha")
    local dir = util.new_temp_dir()
    local file = util.new_temp_file(dir, "buffer.txt")
    stem.add(dir)
    local mount_name = vim.fn.fnamemodify(dir, ":t")
    local mount_path = vim.fn.getcwd() .. "/" .. mount_name
    util.by("Open buffer within mounted path")
    vim.cmd("edit! " .. vim.fn.fnameescape(mount_path .. "/buffer.txt"))
    local buf = vim.api.nvim_get_current_buf()
    util.by("Delete the buffer")
    vim.g.stem_redir = ""
    vim.cmd("redir => g:stem_redir")
    vim.cmd(string.format("silent! lua vim.api.nvim_buf_delete(%d, { force = true })", buf))
    vim.cmd("redir END")
    local captured = vim.g.stem_redir or ""
    util.by("Verify buffer delete did not error")
    assert.is_true(captured:match("E211") == nil)
    util.by("Wait for unmount")
    vim.wait(1000, function()
      return vim.fn.getftype(mount_path) == ""
    end, 50)
    util.by("Verify mount was removed")
    assert.is_true(vim.fn.getftype(mount_path) == "")
  end)

  -- Mount remains while another buffer from it is still open.
  it("keeps mounts while another buffer remains", function()
    util.by("Keep one buffer open while closing another")
    stem.setup({})
    stem.new("")
    local dir = util.new_temp_dir()
    local file1 = util.new_temp_file(dir, "one.txt")
    local file2 = util.new_temp_file(dir, "two.txt")
    stem.add(dir)
    local mount_name = vim.fn.fnamemodify(dir, ":t")
    local mount_path = vim.fn.getcwd() .. "/" .. mount_name
    util.by("Open first buffer")
    vim.cmd("edit! " .. vim.fn.fnameescape(mount_path .. "/one.txt"))
    local buf1 = vim.api.nvim_get_current_buf()
    util.by("Open second buffer")
    vim.cmd("edit! " .. vim.fn.fnameescape(mount_path .. "/two.txt"))
    local buf2 = vim.api.nvim_get_current_buf()
    util.by("Close second buffer")
    vim.api.nvim_buf_delete(buf2, { force = true })
    util.by("Verify mount still exists")
    assert.is_true(vim.fn.getftype(mount_path) == "dir")
    vim.api.nvim_buf_delete(buf1, { force = true })
  end)
end)
