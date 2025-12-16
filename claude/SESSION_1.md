# Session 1: Breakpoint Persistence Overhaul

## Problem

Persistent breakpoints stored as file+line caused errors when switching git branches:

```
Error executing vim.schedule lua callback: .../lua/breakpoints.lua:311: Invalid 'line': out of range
```

Lines could move or files could be truncated, making saved line numbers invalid.

## Solution

Implemented a flexible line locator strategy system with validation guards.

### Configuration Changes

`persist_breakpoints` now accepts multiple formats:

```lua
-- Simple enable (uses defaults)
persist_breakpoints = true

-- Disabled
persist_breakpoints = false

-- Full configuration
persist_breakpoints = {
    enabled = true,
    line_locator = "exact", -- or "hash", "jaccard"
}
```

### Line Locator Strategies

| Strategy | Behavior | Use Case |
|----------|----------|----------|
| `exact` | Restores at saved line number, skips if out of range | Stable codebases |
| `hash` | Matches by SHA256 of trimmed line content | Lines move but content unchanged |
| `jaccard` | Token similarity ≥50%, prefers closer position | Minor edits, variable renames |

### Validation Guards

All strategies now handle edge cases gracefully:
- **File missing**: `breakpoint src/main.rs:42 invalid: file missing`
- **Line out of range**: `breakpoint src/main.rs:999 invalid: out of range`
- **Hash not found**: `breakpoint src/main.rs:42 invalid: hashed line location failed`
- **No similar line**: `breakpoint src/main.rs:42 invalid: no similar line found`

### Extmark Movement Persistence

Added `BufWritePost` autocmd so that when you edit a file in vim (causing extmarks to move) and save, the new positions are persisted.

## Files Created

```
lua/line_locators/
├── init.lua      # Strategy registry
├── exact.lua     # Line number matching
├── hash.lua      # Content hash matching
└── jaccard.lua   # Token similarity matching

tests/persistence_integration_spec.lua  # 15 integration tests
```

## Files Modified

- `lua/options.lua` - Config normalization
- `lua/breakpoints.lua` - Strategy integration, validation guards
- `lua/rust-termdebug.lua` - Pass config to breakpoints module
- `tests/minimal_init.lua` - Fixed packpath for termdebug
- `tests/options_spec.lua` - Updated for new config structure
- `tests/breakpoints_spec.lua` - Updated for new API
- `README.md` - Documented new options

## Strategy Interface

Each locator implements:

```lua
{
    -- Data to store in persistence file
    prepare = function(line_content) -> table|nil

    -- Find matching line in buffer
    find = function(bufnr, stored_data, original_line_0indexed) -> number|nil

    -- Error message when find() returns nil
    failure_reason = "description of failure"
}
```

## Test Results

56 tests passing across 5 spec files:
- options_spec.lua: 16 tests
- breakpoints_spec.lua: 12 tests
- cargo_spec.lua: 7 tests
- persistence_integration_spec.lua: 15 tests
- e2e_spec.lua: 6 tests

## Design Decisions

1. **Strategy modules over inline logic** - Cleaner separation, easier to extend
2. **Backwards compatibility** - Old `line_hash` format still works with hash strategy
3. **No `jaccard-rust`** - Considered Rust-specific tokenization but decided predictable behavior > marginal matching improvement
4. **Threshold 0.5 for jaccard** - Balances flexibility with avoiding false matches
