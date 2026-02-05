.PHONY: test

NVIM ?= nvim
TEST_INIT ?= tests/minimal_init.lua
TEST_DIR ?= tests

test:
	$(NVIM) --headless -u $(TEST_INIT) -c "PlenaryBustedDirectory $(TEST_DIR) { minimal_init = '$(TEST_INIT)' }" -c "qa"
