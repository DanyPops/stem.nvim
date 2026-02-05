.PHONY: test test-behavior test-unit test-default test-oil

NVIM ?= nvim
TEST_INIT ?= tests/minimal_init.lua
TEST_DEFAULT_INIT ?= tests/minimal_init_default.lua
TEST_OIL_INIT ?= tests/minimal_init_oil.lua
TEST_DIR ?= tests
TEST_BEHAVIOR_DIR ?= tests/behavior
TEST_UNIT_DIR ?= tests/unit
TEST_OPTS ?= { minimal_init = '$(TEST_INIT)', sequential = true, keep_going = true }
TEST_DEFAULT_OPTS ?= { minimal_init = '$(TEST_DEFAULT_INIT)', sequential = true, keep_going = true }
TEST_OIL_OPTS ?= { minimal_init = '$(TEST_OIL_INIT)', sequential = true, keep_going = true }
TEST_INTEGRATIONS_DIR ?= tests/behavior/integrations
# sequential keeps output ordered across spec files

test:
	$(NVIM) --headless -u $(TEST_INIT) -c "PlenaryBustedDirectory $(TEST_DIR) $(TEST_OPTS)" -c "qa"

test-behavior:
	$(NVIM) --headless -u $(TEST_INIT) -c "PlenaryBustedDirectory $(TEST_BEHAVIOR_DIR) $(TEST_OPTS)" -c "qa"

test-unit:
	$(NVIM) --headless -u $(TEST_INIT) -c "PlenaryBustedDirectory $(TEST_UNIT_DIR) $(TEST_OPTS)" -c "qa"

test-default:
	$(NVIM) --headless -u $(TEST_DEFAULT_INIT) -c "PlenaryBustedDirectory $(TEST_INTEGRATIONS_DIR) $(TEST_DEFAULT_OPTS)" -c "qa"

test-oil:
	$(NVIM) --headless -u $(TEST_OIL_INIT) -c "PlenaryBustedDirectory $(TEST_INTEGRATIONS_DIR) $(TEST_OIL_OPTS)" -c "qa"
