local constants = require "stem.constants"
local oil = require "stem.integrations.oil"
local util = require "tests.test_util"

describe("stem.nvim oil integration", function()
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
end)
