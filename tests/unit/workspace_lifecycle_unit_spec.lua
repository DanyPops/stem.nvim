local constants = require "stem.constants"
local util = require "tests.test_util"

describe("stem.nvim workspace lifecycle helpers", function()
  local lifecycle

  before_each(function()
    lifecycle = require "stem.workspace_lifecycle"
    util.reset_by()
  end)

  after_each(function()
    util.flush_by()
  end)

  -- set_workspace updates state, mounts roots, and registers workspace.
  it("sets workspace state and registers mounts", function()
    local state = {
      name = nil,
      temporary = true,
      roots = {},
      temp_root = nil,
      prev_cwd = nil,
      mounts = {},
      mount_map = {},
      instance_id = "123",
    }
    local recorded = {
      mounted = nil,
      registered = nil,
      current = nil,
      cwd = nil,
    }
    local ctx = {
      config = { workspace = { bindfs_args = { "--no-allow-other" } }, oil = { follow = false } },
      mount = {
        clear_temp_root = function(_, mounts)
          return mounts
        end,
        mount_roots = function(roots, temp_root, bindfs_args)
          recorded.mounted = { roots = roots, temp_root = temp_root, bindfs_args = bindfs_args }
          return { temp_root .. "/repo" }, { [roots[1]] = "repo" }
        end,
      },
      untitled = {
        temp_root_for = function(_, name, temporary)
          local base = temporary and constants.paths.default_temp_untitled_root or constants.paths.default_temp_root
          return base .. "/" .. name
        end,
      },
      registry = {
        module = {
          register = function(_, id, data)
            recorded.registered = { id = id, data = data }
          end,
          set_mounts = function()
          end,
          set_current = function(_, id)
            recorded.current = id
          end,
        },
        state = {},
      },
      set_cwd = function(path)
        recorded.cwd = path
      end,
      open_root_in_oil = function()
      end,
      events = {
        emit = function()
        end,
      },
    }

    util.by("Apply workspace state with a named workspace")
    lifecycle.set_workspace(state, ctx, "alpha", { "/repo" }, false)

    util.by("Verify state fields updated")
    assert.is_true(state.name == "alpha")
    assert.is_true(state.temporary == false)
    assert.is_true(state.temp_root == constants.paths.default_temp_root .. "/alpha")
    assert.is_true(#state.mounts == 1)

    util.by("Verify mount and registry were invoked")
    assert.is_true(recorded.mounted ~= nil)
    assert.is_true(recorded.registered ~= nil)
    assert.is_true(recorded.current == state.temp_root)
    assert.is_true(recorded.cwd == state.temp_root)
  end)
end)
