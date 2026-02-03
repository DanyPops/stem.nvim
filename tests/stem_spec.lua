local function new_temp_dir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return dir
end

local function new_temp_file(dir, name)
  local path = dir .. "/" .. name
  vim.fn.writefile({ "content" }, path)
  return path
end

local function reset_stem()
  local info = debug.getinfo(1, "S")
  local source = info and info.source or ""
  if source:sub(1, 1) == "@" then
    local path = source:sub(2)
    local root = vim.fn.fnamemodify(path, ":h:h")
    if root and root ~= "" then
      vim.opt.rtp:prepend(root)
      local lua_root = root .. "/lua"
      if not package.path:find(lua_root, 1, true) then
        package.path = package.path
          .. ";" .. lua_root .. "/?.lua"
          .. ";" .. lua_root .. "/?/init.lua"
      end
    end
  end
  package.loaded.stem = nil
  return require "stem"
end

local function capture_notify()
  local messages = {}
  local orig = vim.notify
  vim.notify = function(msg, level, opts)
    table.insert(messages, { msg = msg, level = level, opts = opts })
  end
  return messages, function()
    vim.notify = orig
  end
end

describe("stem.nvim", function()
  local stem
  local data_home

  local function require_bindfs()
    if vim.fn.executable("bindfs") ~= 1 or vim.fn.filereadable("/dev/fuse") == 0 then
      error("bindfs or /dev/fuse missing for tests")
    end
    return true
  end

  before_each(function()
    data_home = vim.fn.stdpath "data"
    stem = reset_stem()
    local temp_cwd = new_temp_dir()
    vim.cmd("cd " .. vim.fn.fnameescape(temp_cwd))
    vim.cmd("tcd " .. vim.fn.fnameescape(temp_cwd))
  end)

  after_each(function()
    pcall(stem.close)
  end)

  it("bootstraps bindfs and FUSE availability", function()
    local has_bindfs = vim.fn.executable("bindfs") == 1
    local has_fuse = vim.fn.filereadable("/dev/fuse") == 1
    local ok, err = pcall(stem.setup, {})
    if has_bindfs and has_fuse then
      assert.is_true(ok)
    else
      assert.is_false(ok)
      assert.is_true(type(err) == "string" and err ~= "")
    end
  end)

  it("creates an unnamed workspace with expected cwd", function()
    if not require_bindfs() then
      return
    end
    stem.new("")
    local cwd = vim.fn.getcwd()
    local temp_root = vim.env.STEM_TMP_UNTITLED_ROOT or "/tmp/stem/temporary"
    assert.is_true(cwd:match(vim.pesc(temp_root) .. "/untitled$") ~= nil)
    assert.is_true(vim.fn.isdirectory(cwd) == 1)
  end)

  it("adds and removes directories", function()
    if not require_bindfs() then
      return
    end
    stem.new("")
    local dir = new_temp_dir()
    stem.add(dir)
    local mount_name = vim.fn.fnamemodify(dir, ":t")
    local mount_path = vim.fn.getcwd() .. "/" .. mount_name
    assert.is_true(vim.fn.getftype(mount_path) == "dir")
    stem.remove(dir)
    assert.is_true(vim.fn.getftype(mount_path) == "")
  end)

  it("bindfs-backed mount is created successfully", function()
    if not require_bindfs() then
      return
    end
    stem.new("")
    local dir = new_temp_dir()
    stem.add(dir)
    local mount_name = vim.fn.fnamemodify(dir, ":t")
    local mount_path = vim.fn.getcwd() .. "/" .. mount_name
    assert.is_true(vim.fn.getftype(mount_path) == "dir")
  end)

  it("saves and opens a workspace", function()
    if not require_bindfs() then
      return
    end
    local dir = new_temp_dir()
    stem.new("")
    stem.add(dir)
    stem.save("alpha")
    local ws_file = data_home .. "/stem/workspaces/alpha.lua"
    assert.is_true(vim.fn.filereadable(ws_file) == 1)
    stem.close()
    stem.open("alpha")
    local named_root = vim.env.STEM_TMP_ROOT or "/tmp/stem/named"
    assert.is_true(vim.fn.getcwd():match(vim.pesc(named_root) .. "/alpha$") ~= nil)
  end)

  it("renames a workspace", function()
    if not require_bindfs() then
      return
    end
    stem.new("")
    stem.save("one")
    stem.rename("one", "two")
    local old_file = data_home .. "/stem/workspaces/one.lua"
    local new_file = data_home .. "/stem/workspaces/two.lua"
    assert.is_true(vim.fn.filereadable(old_file) == 0)
    assert.is_true(vim.fn.filereadable(new_file) == 1)
  end)

  it("lists workspaces and reports status", function()
    if not require_bindfs() then
      return
    end
    local messages, restore = capture_notify()
    stem.new("")
    stem.save("listme")
    stem.list()
    stem.status()
    restore()
    local joined = {}
    for _, item in ipairs(messages) do
      table.insert(joined, item.msg)
    end
    local all = table.concat(joined, "\n")
    assert.is_true(all:match("listme") ~= nil)
    assert.is_true(all:match("Workspace:") ~= nil)
  end)

  it("writes and loads sessions for named workspaces", function()
    if not require_bindfs() then
      return
    end
    local dir = new_temp_dir()
    local file = new_temp_file(dir, "file.txt")
    stem.new("sess")
    vim.cmd("edit " .. vim.fn.fnameescape(file))
    stem.save("sess")
    stem.close()
    local session_path = data_home .. "/stem/sessions/sess.vim"
    assert.is_true(vim.fn.filereadable(session_path) == 1)
    stem.open("sess")
    assert.is_true(vim.fn.filereadable(session_path) == 1)
  end)

  it("does not abandon modified buffers during session load", function()
    if not require_bindfs() then
      return
    end
    local dir = new_temp_dir()
    local file = new_temp_file(dir, "conflict.txt")
    stem.new("conflict")
    vim.cmd("edit " .. vim.fn.fnameescape(file))
    stem.save("conflict")
    stem.close()

    vim.o.hidden = false
    vim.cmd "enew"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "dirty" })
    vim.bo.modified = true

    stem.open("conflict")
    assert.is_true(vim.bo.modified == true)
  end)

  it("lists untitled workspaces", function()
    if not require_bindfs() then
      return
    end
    local messages, restore = capture_notify()
    stem.new("")
    stem.untitled_list()
    restore()
    local joined = {}
    for _, item in ipairs(messages) do
      table.insert(joined, item.msg)
    end
    local all = table.concat(joined, "\n")
    assert.is_true(all:match("Untitled workspaces:") ~= nil)
    assert.is_true(all:match("untitled") ~= nil)
  end)

  it("clears all untitled workspaces when last instance closes", function()
    if not require_bindfs() then
      return
    end
    stem.new("")
    local base = vim.env.STEM_TMP_UNTITLED_ROOT or "/tmp/stem/temporary"
    local extra = base .. "/untitled1"
    vim.fn.mkdir(extra, "p")
    stem.close()
    local remaining = vim.fn.readdir(base)
    local has_dirs = false
    for _, entry in ipairs(remaining) do
      if entry ~= ".locks" then
        has_dirs = true
      end
    end
    assert.is_true(has_dirs == false)
  end)

  it("keeps other untitled workspaces when another instance is active", function()
    if not require_bindfs() then
      return
    end
    stem.new("")
    local base = vim.env.STEM_TMP_UNTITLED_ROOT or "/tmp/stem/temporary"
    local other = base .. "/untitled1"
    vim.fn.mkdir(other, "p")
    local lock_dir = base .. "/.locks"
    vim.fn.mkdir(lock_dir, "p")
    vim.fn.writefile({ "other" }, lock_dir .. "/other-instance")
    stem.close()
    assert.is_true(vim.fn.isdirectory(other) == 1)
  end)

  it("accepts relative paths for StemAdd", function()
    if not require_bindfs() then
      return
    end
    local base = new_temp_dir()
    local rel = base .. "/relrepo"
    vim.fn.mkdir(rel, "p")
    stem.new("")
    local temp_root = vim.fn.getcwd()
    vim.cmd("cd " .. vim.fn.fnameescape(base))
    vim.cmd("tcd " .. vim.fn.fnameescape(base))
    stem.add("relrepo")
    vim.cmd("cd " .. vim.fn.fnameescape(temp_root))
    vim.cmd("tcd " .. vim.fn.fnameescape(temp_root))
    local mount_path = temp_root .. "/relrepo"
    assert.is_true(vim.fn.getftype(mount_path) == "dir")
  end)

  it("reports bindfs mount failures", function()
    if not require_bindfs() then
      return
    end
    local messages, restore = capture_notify()
    stem.setup({ workspace = { bindfs_args = { "--not-a-real-flag" } } })
    stem.new("")
    local dir = new_temp_dir()
    stem.add(dir)
    restore()
    local saw_failure = false
    for _, item in ipairs(messages) do
      if item.msg:match("Failed to bindfs") then
        saw_failure = true
      end
    end
    assert.is_true(saw_failure)
  end)

  it("disambiguates duplicate root names when mounting", function()
    if not require_bindfs() then
      return
    end
    local base = new_temp_dir()
    local repo1 = base .. "/repo"
    local repo2 = base .. "/other/repo"
    vim.fn.mkdir(repo1, "p")
    vim.fn.mkdir(repo2, "p")
    stem.new("")
    stem.add(repo1)
    stem.add(repo2)
    local cwd = vim.fn.getcwd()
    assert.is_true(vim.fn.getftype(cwd .. "/repo") == "dir")
    assert.is_true(vim.fn.getftype(cwd .. "/repo__2") == "dir")
  end)

  it("rejects invalid workspace names on save", function()
    if not require_bindfs() then
      return
    end
    local messages, restore = capture_notify()
    stem.new("")
    stem.save("bad/name")
    restore()
    local ws_file = data_home .. "/stem/workspaces/bad/name.lua"
    assert.is_true(vim.fn.filereadable(ws_file) == 0)
    local saw_invalid = false
    for _, item in ipairs(messages) do
      if item.msg:match("Invalid workspace name") then
        saw_invalid = true
      end
    end
    assert.is_true(saw_invalid)
  end)

  it("rejects non-existent workspace on open", function()
    local messages, restore = capture_notify()
    stem.open("missing")
    restore()
    local saw_missing = false
    for _, item in ipairs(messages) do
      if item.msg:match("Workspace not found") then
        saw_missing = true
      end
    end
    assert.is_true(saw_missing)
  end)

  it("rejects non-directory on add", function()
    if not require_bindfs() then
      return
    end
    local dir = new_temp_dir()
    local file = new_temp_file(dir, "notadir.txt")
    local messages, restore = capture_notify()
    stem.new("")
    stem.add(file)
    restore()
    local saw_error = false
    for _, item in ipairs(messages) do
      if item.msg:match("Not a directory") then
        saw_error = true
      end
    end
    assert.is_true(saw_error)
  end)

  it("rejects unknown directory on remove", function()
    if not require_bindfs() then
      return
    end
    local dir = new_temp_dir()
    local messages, restore = capture_notify()
    stem.new("")
    stem.remove(dir)
    restore()
    local saw_error = false
    for _, item in ipairs(messages) do
      if item.msg:match("Directory not found") then
        saw_error = true
      end
    end
    assert.is_true(saw_error)
  end)

  it("prevents renaming to an existing workspace", function()
    if not require_bindfs() then
      return
    end
    local messages, restore = capture_notify()
    stem.new("")
    stem.save("one")
    stem.new("")
    stem.save("two")
    stem.rename("one", "two")
    restore()
    local saw_error = false
    for _, item in ipairs(messages) do
      if item.msg:match("Workspace already exists") then
        saw_error = true
      end
    end
    assert.is_true(saw_error)
  end)

  it("completes StemOpen from saved workspaces", function()
    if not require_bindfs() then
      return
    end
    stem.new("")
    stem.save("alpha")
    local items = stem._complete.workspaces("a")
    assert.is_true(vim.tbl_contains(items, "alpha"))
  end)

  it("completes StemSave from saved workspaces", function()
    if not require_bindfs() then
      return
    end
    stem.new("")
    stem.save("bravo")
    local items = stem._complete.workspaces("b")
    assert.is_true(vim.tbl_contains(items, "bravo"))
  end)

  it("completes StemRemove from current roots", function()
    if not require_bindfs() then
      return
    end
    stem.new("")
    local dir = new_temp_dir()
    stem.add(dir)
    local items = stem._complete.roots(dir:sub(1, 3))
    assert.is_true(vim.tbl_contains(items, dir))
  end)

  it("completes StemRename first arg from workspaces", function()
    if not require_bindfs() then
      return
    end
    stem.new("")
    stem.save("charlie")
    local items = stem._complete.rename("c", "StemRename c")
    assert.is_true(vim.tbl_contains(items, "charlie"))
  end)
end)
