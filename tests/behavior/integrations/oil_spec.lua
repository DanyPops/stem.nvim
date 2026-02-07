local constants = require "stem.constants"
local oil = require "stem.integrations.oil"
local util = require "tests.test_util"

describe("stem.nvim oil integration", function()
  local stem

  before_each(function()
    util.reset_by()
  end)

  after_each(function()
    util.flush_by()
  end)

  -- Availability reflects whether oil is loaded.
  it("detects oil availability", function()
    util.by("Check availability in current test context")
    local available = oil.is_available({ oil = { enabled = true } })
    if vim.g.stem_test_oil then
      assert.is_true(available)
    else
      assert.is_false(available)
    end
  end)

  -- Oil current dir only resolves when oil is loaded.
  it("returns oil current dir when loaded", function()
    util.by("Create an oil buffer and query current dir")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, "oil-test://root")
    vim.bo[buf].filetype = constants.oil.filetype
    local dir = oil.current_dir(buf, { oil = { enabled = true } })
    if vim.g.stem_test_oil then
      assert.is_true(dir == vim.g.stem_test_oil_dir)
    else
      assert.is_nil(dir)
    end
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  -- Open root is a no-op when oil is missing.
  it("opens root only when oil is available", function()
    util.by("Attempt to open root via integration")
    local prev = vim.bo.filetype
    vim.bo.filetype = constants.oil.filetype
    vim.g.stem_test_oil_opened = nil
    oil.open_root({ oil = { enabled = true, follow = true } }, "/tmp/oil-root")
    if vim.g.stem_test_oil then
      assert.is_true(vim.g.stem_test_oil_opened == "/tmp/oil-root")
    else
      assert.is_nil(vim.g.stem_test_oil_opened)
    end
    vim.bo.filetype = prev
  end)

  -- Closing a workspace from an oil buffer should not return to original cwd.
  it("does not return oil buffer to original cwd after close", function()
    util.by("Ensure bindfs is available and reset editor")
    util.ensure_bindfs()
    stem = util.reset_stem()
    util.reset_editor()

    local original_dir = util.new_temp_dir()
    vim.cmd("cd " .. vim.fn.fnameescape(original_dir))
    vim.cmd("tcd " .. vim.fn.fnameescape(original_dir))

    util.by("Open an oil buffer rooted at the original cwd")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, "oil://" .. original_dir .. "/")
    vim.bo[buf].filetype = constants.oil.filetype
    vim.api.nvim_win_set_buf(0, buf)
    vim.g.stem_test_oil_dir = original_dir

    local oil_mod = require "oil"
    local original_open = oil_mod.open
    oil_mod.open = function(path)
      vim.g.stem_test_oil_opened = path
      vim.g.stem_test_oil_dir = path
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_set_name(buf, "oil://" .. path .. "/")
      end
    end

    local dir_autocmd = vim.api.nvim_create_autocmd("DirChanged", {
      callback = function()
        if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == constants.oil.filetype then
          local cwd = vim.fn.getcwd()
          vim.g.stem_test_oil_dir = cwd
          vim.api.nvim_buf_set_name(buf, "oil://" .. cwd .. "/")
        end
      end,
    })

    util.by("Create an unnamed workspace and follow into temp root")
    stem.new("")
    local temp_root = vim.fn.getcwd()
    assert.is_true(vim.g.stem_test_oil_dir == temp_root)

    util.by("Confirm close and return to original cwd")
    local original_confirm = vim.fn.confirm
    local original_list_uis = vim.api.nvim_list_uis
    vim.fn.confirm = function()
      return 1
    end
    vim.api.nvim_list_uis = function()
      return { {} }
    end
    local closed = stem.close()
    vim.fn.confirm = original_confirm
    vim.api.nvim_list_uis = original_list_uis

    assert.is_true(closed)
    assert.is_true(vim.fn.getcwd() == original_dir)
    if vim.api.nvim_buf_is_valid(buf) then
      assert.is_false(vim.api.nvim_buf_get_name(buf) == "oil://" .. original_dir .. "/")
    end

    if dir_autocmd then
      pcall(vim.api.nvim_del_autocmd, dir_autocmd)
    end
    oil_mod.open = original_open
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)
end)
