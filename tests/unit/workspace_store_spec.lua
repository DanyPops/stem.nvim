local constants = require "stem.constants"
local util = require "tests.test_util"

describe("stem.nvim workspace store", function()
  local store
  local data_home
  local ws_dir

  before_each(function()
    store = require "stem.ws.store"
    data_home = vim.fn.stdpath "data"
    ws_dir = data_home .. "/" .. constants.paths.workspace_dir
    vim.fn.delete(ws_dir, "rf")
    vim.fn.mkdir(ws_dir, "p")
    util.reset_by()
  end)

  after_each(function()
    util.flush_by()
  end)

  -- Valid workspace names are constrained to safe filesystem characters.
  it("validates workspace names", function()
    util.by("Accept safe name characters")
    assert.is_true(store.is_valid_name("alpha-1_test.vim"))

    util.by("Reject empty and unsafe names")
    assert.is_false(store.is_valid_name(""))
    assert.is_false(store.is_valid_name("bad name"))
    assert.is_false(store.is_valid_name("../oops"))
  end)

  -- Writes include a schema version and persist roots.
  it("writes schema versioned roots", function()
    util.by("Write a workspace with one root")
    local root = util.new_temp_dir()
    local ok = store.write("alpha", { root })
    assert.is_true(ok)

    util.by("Read back schema version and roots")
    local entry = store.read("alpha")
    assert.is_true(type(entry) == "table")
    assert.is_true(entry.version == 1)
    assert.is_true(type(entry.roots) == "table")
    assert.is_true(#entry.roots == 1)
    assert.is_true(entry.roots[1] == root)
  end)

  -- Invalid names should not create files.
  it("rejects invalid names on write", function()
    util.by("Attempt to write an invalid name")
    local ok = store.write("bad name", { util.new_temp_dir() })
    assert.is_false(ok)
  end)

  -- Failed writes must not corrupt the existing file.
  it("keeps prior data when write fails", function()
    util.by("Write an initial workspace entry")
    local root = util.new_temp_dir()
    assert.is_true(store.write("alpha", { root }))

    util.by("Simulate write failure")
    local orig = vim.fn.writefile
    vim.fn.writefile = function()
      error("write failed")
    end
    local ok, result = pcall(store.write, "alpha", { util.new_temp_dir() })
    vim.fn.writefile = orig
    assert.is_true(ok)
    assert.is_false(result)

    util.by("Verify original data still readable")
    local entry = store.read("alpha")
    assert.is_true(entry and type(entry.roots) == "table")
    assert.is_true(#entry.roots == 1)
    assert.is_true(entry.roots[1] == root)
  end)
end)
