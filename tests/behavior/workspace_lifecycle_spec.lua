local constants = require "stem.constants"
local util = require "tests.test_util"

describe("stem.nvim workspace lifecycle", function()
  local stem
  local data_home
  local cleanup_paths = {}

  local function queue_cleanup(path)
    if path and path ~= "" then
      table.insert(cleanup_paths, path)
    end
  end

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
    for _, path in ipairs(cleanup_paths) do
      pcall(vim.fn.delete, path, "rf")
    end
    cleanup_paths = {}
    util.flush_by()
  end)

  -- Setup succeeds only when bindfs and FUSE are available.
  it("bootstraps bindfs and FUSE availability", function()
    util.by("Check bindfs and /dev/fuse availability before setup")
    local has_bindfs = vim.fn.executable(constants.commands.bindfs) == 1
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
    local temp_root = vim.env.STEM_TMP_UNTITLED_ROOT or constants.paths.default_temp_untitled_root
    assert.is_true(cwd:match(vim.pesc(temp_root) .. "/untitled$") ~= nil)
    assert.is_true(vim.fn.isdirectory(cwd) == 1)
  end)

  -- Declining close keeps the unnamed workspace open.
  it("refuses to close unnamed workspace when user declines", function()
    util.by("Open unnamed workspace and add a root")
    local dir = util.new_temp_dir()
    stem.new("")
    stem.add(dir)

    local original_confirm = vim.fn.confirm
    local original_list_uis = vim.api.nvim_list_uis
    local confirm_calls = 0
    local messages, restore = util.capture_notify()
    vim.fn.confirm = function()
      confirm_calls = confirm_calls + 1
      return 2
    end
    vim.api.nvim_list_uis = function()
      return { {} }
    end

    local ok, err = pcall(function()
      local temp_root = vim.env.STEM_TMP_UNTITLED_ROOT or constants.paths.default_temp_untitled_root
      local cwd_before = vim.fn.getcwd()
      local lock_path = require("stem.ws.untitled_store").instance_lock_path({
        temp_untitled_root = temp_root,
      }, tostring(vim.fn.getpid()))

      util.by("Attempt to close and decline confirmation")
      local closed = stem.close()
      assert.is_false(closed)
      local cwd = vim.fn.getcwd()
      assert.is_true(cwd:match(vim.pesc(temp_root) .. "/untitled") ~= nil)
      assert.is_true(cwd == cwd_before)
      assert.is_true(vim.fn.isdirectory(cwd) == 1)
      assert.is_true(vim.fn.filereadable(lock_path) == 1)
      assert.is_true(confirm_calls == 1)
      local closed_message = constants.messages.workspace_closed
      for _, item in ipairs(messages) do
        assert.is_true(item.msg ~= closed_message)
      end
    end)

    vim.fn.confirm = original_confirm
    vim.api.nvim_list_uis = original_list_uis
    restore()
    if not ok then
      error(err)
    end
  end)

  -- QuitPre pre-exit autocmd blocks editor quit on close decline.
  it("QuitPre pre-exit autocmd blocks editor quit on close decline", function()
    util.by("Ensure QuitPre autocmds are registered")
    stem.setup({})

    util.by("Open unnamed workspace and add a root")
    local dir = util.new_temp_dir()
    stem.new("")
    stem.add(dir)

    local original_confirm = vim.fn.confirm
    local original_list_uis = vim.api.nvim_list_uis
    vim.fn.confirm = function()
      return 2
    end
    vim.api.nvim_list_uis = function()
      return { {} }
    end

    local ok_set = pcall(vim.api.nvim_set_vvar, "exiting", 1)
    pcall(vim.api.nvim_set_vvar, "errmsg", "")
    local ok, err = pcall(function()
      util.by("Simulate QuitPre handling")
      vim.api.nvim_exec_autocmds("QuitPre", {})
    end)

    vim.fn.confirm = original_confirm
    vim.api.nvim_list_uis = original_list_uis
    if ok_set then
      pcall(vim.api.nvim_set_vvar, "exiting", 0)
    end

    local errmsg = ""
    pcall(function()
      errmsg = vim.api.nvim_get_vvar("errmsg")
    end)
    if errmsg ~= "" then
      ok = false
      err = errmsg
    end
    assert.is_true(ok, err)
  end)

  -- Adding a root should not leave the original buffer open.
  it("replaces the original buffer with mounted path", function()
    util.by("Create a file and open it")
    local dir = util.new_temp_dir()
    local file = util.new_temp_file(dir, "dup.txt")
    vim.cmd("cd " .. vim.fn.fnameescape(dir))
    vim.cmd("edit " .. vim.fn.fnameescape(file))

    util.by("Add root to workspace")
    stem.add(dir)

    util.by("Verify original buffer is not still open")
    local temp_root = vim.fn.getcwd()
    local filename = "/dup.txt"
    local has_original = false
    local has_mounted = false
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        local name = vim.api.nvim_buf_get_name(bufnr)
        if name == file then
          has_original = true
        end
        if name:find(temp_root, 1, true) == 1 and name:sub(-#filename) == filename then
          has_mounted = true
        end
      end
    end
    assert.is_true(has_mounted)
    assert.is_false(has_original)
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
    local ws_file = data_home .. "/" .. constants.paths.workspace_dir .. "/alpha.lua"
    assert.is_true(vim.fn.filereadable(ws_file) == 1)
    util.by("Close workspace before reopening")
    stem.close()
    util.by("Open saved workspace")
    stem.open("alpha")
    local named_root = vim.env.STEM_TMP_ROOT or constants.paths.default_temp_root
    util.by("Verify named root cwd")
    assert.is_true(vim.fn.getcwd():match(vim.pesc(named_root) .. "/alpha$") ~= nil)
  end)

  -- Opening a saved workspace after restart should use named temp root.
  it("opens saved workspace in named root after restart", function()
    local prev_tmp_root = vim.env.STEM_TMP_ROOT
    local prev_tmp_untitled = vim.env.STEM_TMP_UNTITLED_ROOT
    vim.env.STEM_TMP_ROOT = "/tmp/stem/named"
    vim.env.STEM_TMP_UNTITLED_ROOT = "/tmp/temporary/untitled"

    util.by("Reload stem with custom temp roots")
    stem = util.reset_stem()
    util.reset_editor()

    util.by("Create a root directory with a dummy file")
    local dir = util.new_temp_dir()
    local file = util.new_temp_file(dir, "dummy.txt")

    util.by("Start in the root directory")
    vim.cmd("cd " .. vim.fn.fnameescape(dir))
    vim.cmd("tcd " .. vim.fn.fnameescape(dir))
    vim.cmd("edit " .. vim.fn.fnameescape(file))

    util.by("Add cwd to a new workspace and save it")
    stem.add("")
    stem.save("restart-ws")
    stem.close()

    util.by("Restart stem and reopen from root directory")
    stem = util.reset_stem()
    util.reset_editor()
    vim.cmd("cd " .. vim.fn.fnameescape(dir))
    vim.cmd("tcd " .. vim.fn.fnameescape(dir))
    vim.cmd("edit " .. vim.fn.fnameescape(file))
    stem.open("restart-ws")

    util.by("Verify named root cwd (not untitled root)")
    local named_root = vim.env.STEM_TMP_ROOT or constants.paths.default_temp_root
    assert.is_true(vim.fn.getcwd():match(vim.pesc(named_root) .. "/restart%-ws$") ~= nil)

    vim.env.STEM_TMP_ROOT = prev_tmp_root
    vim.env.STEM_TMP_UNTITLED_ROOT = prev_tmp_untitled
  end)

  -- Renaming a workspace moves its stored file.
  it("renames a workspace", function()
    util.by("Save and rename a workspace")
    stem.new("")
    util.by("Save workspace as one")
    stem.save("one")
    util.by("Rename workspace to two")
    stem.rename("one", "two")
    local old_file = data_home .. "/" .. constants.paths.workspace_dir .. "/one.lua"
    local new_file = data_home .. "/" .. constants.paths.workspace_dir .. "/two.lua"
    util.by("Verify old file removed and new file exists")
    assert.is_true(vim.fn.filereadable(old_file) == 0)
    assert.is_true(vim.fn.filereadable(new_file) == 1)
  end)

  -- Deleting a workspace removes its stored file.
  it("deletes a saved workspace", function()
    util.by("Save a workspace to delete")
    stem.new("")
    stem.save("delete-me")
    local ws_file = data_home .. "/" .. constants.paths.workspace_dir .. "/delete-me.lua"
    local session_file = data_home .. "/" .. constants.paths.session_dir .. "/delete-me.vim"
    queue_cleanup(ws_file)
    queue_cleanup(session_file)
    assert.is_true(vim.fn.filereadable(ws_file) == 1)

    util.by("Delete the saved workspace")
    stem.delete("delete-me")
    assert.is_true(vim.fn.filereadable(ws_file) == 0)
    assert.is_true(vim.fn.filereadable(session_file) == 0)
  end)

  -- Deleting should refuse when another instance holds a lock.
  it("refuses to delete a locked workspace", function()
    util.by("Save a workspace to delete")
    stem.new("")
    stem.save("locked-ws")
    local ws_file = data_home .. "/" .. constants.paths.workspace_dir .. "/locked-ws.lua"
    local session_file = data_home .. "/" .. constants.paths.session_dir .. "/locked-ws.vim"
    queue_cleanup(ws_file)
    queue_cleanup(session_file)
    assert.is_true(vim.fn.filereadable(ws_file) == 1)

    util.by("Create a lock from another instance")
    local locks = require "stem.ws.locks"
    local lock_config = { temp_root = vim.env.STEM_TMP_ROOT or constants.paths.default_temp_root }
    locks.ensure_instance_lock(lock_config, "locked-ws", "other-instance")
    queue_cleanup(lock_config.temp_root .. "/" .. constants.names.locks_dir)

    util.by("Attempt to delete locked workspace")
    local messages, restore = util.capture_notify()
    stem.delete("locked-ws")
    restore()
    assert.is_true(vim.fn.filereadable(ws_file) == 1)
    local expected = string.format(constants.messages.workspace_locked, "locked-ws")
    local found = false
    for _, item in ipairs(messages) do
      if item.msg and item.msg:find(expected, 1, true) then
        found = true
        break
      end
    end
    assert.is_true(found)
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
    assert.is_true(all:match(vim.pesc(constants.messages.status_header)) ~= nil)
  end)

  -- List shows untitled workspaces before saved ones.
  it("lists untitled workspaces above saved ones", function()
    util.by("Create a saved workspace")
    stem.new("")
    stem.save("saved1")
    stem.close()

    util.by("Create an untitled workspace")
    local messages, restore = util.capture_notify()
    stem.new("")
    local untitled_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")

    util.by("List workspaces")
    stem.list()
    restore()

    local joined = {}
    for _, item in ipairs(messages) do
      table.insert(joined, item.msg)
    end
    local all = table.concat(joined, "\n")
    local lines = vim.split(all, "\n")

    local untitled_idx = nil
    local saved_idx = nil
    for i, line in ipairs(lines) do
      if line:match("^ %- " .. vim.pesc(untitled_name) .. " ?%*?$") then
        untitled_idx = i
      end
      if line:match("^ %- saved1 ?%*?$") then
        saved_idx = i
      end
    end
    util.by("Verify untitled appears before saved workspace")
    assert.is_true(untitled_idx ~= nil)
    assert.is_true(saved_idx ~= nil)
    assert.is_true(untitled_idx < saved_idx)
  end)

  -- Workspace info shows roots for current and saved workspaces.
  it("reports workspace roots via StemInfo", function()
    util.by("Create a workspace with two roots")
    local messages, restore = util.capture_notify()
    stem.new("")
    local dir1 = util.new_temp_dir()
    local dir2 = util.new_temp_dir()
    stem.add(dir1)
    stem.add(dir2)
    util.by("Remove one root and reuse it in another workspace")
    stem.remove(dir2)
    util.by("Show info for current workspace")
    stem.info("")
    util.by("Save workspace and show info by name")
    stem.save("info-me")
    stem.info("info-me")
    util.by("Open another workspace and add the removed root")
    stem.new("info-two")
    stem.add(dir2)
    stem.info("info-two")
    restore()
    local joined = {}
    for _, item in ipairs(messages) do
      table.insert(joined, item.msg)
    end
    local all = table.concat(joined, "\n")
    util.by("Verify info output includes roots")
    assert.is_true(all:match(vim.pesc(constants.messages.status_header)) ~= nil)
    assert.is_true(all:match(vim.pesc(dir1)) ~= nil)
    assert.is_true(all:match(vim.pesc(dir2)) ~= nil)
  end)

  -- Opening a workspace prunes missing roots from the store.
  it("prunes missing roots when opening a workspace", function()
    util.by("Create and save a workspace with two roots")
    stem.new("")
    local dir1 = util.new_temp_dir()
    local dir2 = util.new_temp_dir()
    stem.add(dir1)
    stem.add(dir2)
    stem.save("missing-root")
    stem.close()

    util.by("Delete one root before opening")
    local store = require "stem.ws.store"
    local saved = store.read("missing-root")
    assert.is_true(saved and type(saved.roots) == "table")
    local found = false
    for _, root in ipairs(saved.roots) do
      if root == dir2 then
        found = true
        break
      end
    end
    assert.is_true(found)
    local deleted = vim.fn.delete(dir2, "rf")
    assert.is_true(deleted == 0)
    assert.is_true(vim.fn.isdirectory(dir2) == 0)

    util.by("Open workspace and capture missing-root notification")
    local messages, restore = util.capture_notify()
    stem.open("missing-root")
    restore()

    util.by("Verify missing root was reported")
    local joined = {}
    for _, item in ipairs(messages) do
      table.insert(joined, item.msg)
    end
    local all = table.concat(joined, "\n")
    assert.is_true(all:match(vim.pesc(dir2)) ~= nil)

    util.by("Verify store was updated to remove missing root")
    local entry = store.read("missing-root")
    assert.is_true(entry and type(entry.roots) == "table")
    local has_dir1 = false
    local has_dir2 = false
    for _, root in ipairs(entry.roots) do
      if root == dir1 then
        has_dir1 = true
      end
      if root == dir2 then
        has_dir2 = true
      end
    end
    assert.is_true(has_dir1)
    assert.is_true(has_dir2 == false)
  end)
end)
