local util = require "tests.test_util"

describe("stem.nvim workspace effects", function()
  local effects
  local original_cmd

  before_each(function()
    effects = require "stem.workspace_effects"
    original_cmd = vim.cmd
    util.reset_by()
  end)

  after_each(function()
    vim.cmd = original_cmd
    util.flush_by()
  end)

  -- set_cwd should issue cd and tcd commands.
  it("sets global and tab-local cwd", function()
    local commands = {}
    vim.cmd = function(cmd)
      table.insert(commands, cmd)
    end

    util.by("Set cwd to a path")
    effects.set_cwd("/tmp/example")

    util.by("Verify cd and tcd were issued")
    assert.is_true(commands[1]:match("^cd ") ~= nil)
    assert.is_true(commands[2]:match("^tcd ") ~= nil)
  end)

  -- open_root_in_oil should open only for oil buffers and follow enabled.
  it("opens root in oil when following", function()
    local opened = nil
    local original_oil = package.loaded.oil
    package.loaded.oil = {
      open = function(path)
        opened = path
      end,
    }

    util.by("Skip open when not in oil buffer")
    vim.bo.filetype = ""
    effects.open_root_in_oil({ oil = { follow = true } }, "/tmp/root")
    assert.is_true(opened == nil)

    util.by("Open root when in oil buffer")
    vim.bo.filetype = "oil"
    effects.open_root_in_oil({ oil = { follow = true } }, "/tmp/root")
    assert.is_true(opened == "/tmp/root")

    package.loaded.oil = original_oil
  end)
end)
