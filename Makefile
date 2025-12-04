.PHONY: test test-setup clean

test-setup:
	@echo "Setting up test fixtures..."
	@cd tests/fixtures/test-project && cargo build 2>/dev/null || true

test: test-setup
	@echo "Running tests..."
	nvim --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"

clean:
	@echo "Cleaning test artifacts..."
	@rm -rf tests/fixtures/test-project/target
	@rm -rf tests/fixtures/test-project/*/target
	@rm -rf /tmp/nvim
