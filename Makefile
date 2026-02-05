.PHONY: test test-behavior test-unit

NVIM ?= nvim
TEST_INIT ?= tests/minimal_init.lua
TEST_DIR ?= tests
TEST_BEHAVIOR_DIR ?= tests/behavior
TEST_UNIT_DIR ?= tests/unit
TEST_OPTS ?= { minimal_init = '$(TEST_INIT)', sequential = true, keep_going = true }
# sequential keeps output ordered across spec files

test:
	$(NVIM) --headless -u $(TEST_INIT) -c "PlenaryBustedDirectory $(TEST_DIR) $(TEST_OPTS)" -c "qa"

test-behavior:
	$(NVIM) --headless -u $(TEST_INIT) -c "PlenaryBustedDirectory $(TEST_BEHAVIOR_DIR) $(TEST_OPTS)" -c "qa"

test-unit:
	$(NVIM) --headless -u $(TEST_INIT) -c "PlenaryBustedDirectory $(TEST_UNIT_DIR) $(TEST_OPTS)" -c "qa"
