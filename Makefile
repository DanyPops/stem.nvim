.PHONY: test

NVIM ?= nvim
TEST_INIT ?= tests/minimal_init.lua
TEST_DIR ?= tests
TEST_OPTS ?= { minimal_init = '$(TEST_INIT)', sequential = true, keep_going = true }
# sequential keeps output ordered across spec files

test:
	$(NVIM) --headless -u $(TEST_INIT) -c "PlenaryBustedDirectory $(TEST_DIR) $(TEST_OPTS)" -c "qa"
