# Tests

Basic smoke tests for rust-termdebug.nvim using [plenary.nvim](https://github.com/nvim-lua/plenary.nvim).

## Running Tests

```bash
make test
```

Or manually:

```bash
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"
```

## Test Structure

- `tests/cargo_spec.lua` - Tests for cargo module functions
- `tests/fixtures/test-project/` - A Rust workspace with multiple crates for testing
- `tests/minimal_init.lua` - Minimal Neovim configuration for running tests

## Test Coverage

Current tests cover:
- `cargo.metadata()` - Workspace metadata parsing
- `cargo.current_crate_name()` - Crate name resolution from file paths
- `cargo.build_tests()` - Test compilation and artifact collection
- `cargo.build_benches()` - Benchmark compilation and artifact collection
- `cargo.clear_pins()` - Pin clearing functionality

## Cleaning Up

```bash
make clean
```

This removes build artifacts and temporary test files.
