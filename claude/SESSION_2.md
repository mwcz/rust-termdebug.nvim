# Session 2: Build Profile Selection

## Objective
Add ability to debug release builds with debug symbols by allowing profile selection in the binary debug workflow (`<leader>ds`).

## Approach Discussion
- Investigated programmatic detection of available profiles and debug symbol status
- Determined that `cargo metadata` does not expose profile info; requires TOML parsing
- Decided to skip debug symbol detection (user will get GDB warning if missing)
- Profile selection integrated directly into the existing binary selection menu (frictionless UX)
- Tests and benches excluded (they have their own profiles)
- Custom profiles detected by parsing `[profile.X]` headers from Cargo.toml

## Implementation

### New Helper Functions (`cargo.lua` lines 7-46)
- `profile_to_target_dir(profile)` - Maps "dev" to "debug", others pass through
- `profile_to_build_flag(profile)` - Maps "dev" to "", "release" to "--release", custom to "--profile X"
- `get_available_profiles(workspace_root)` - Parses `[profile.X]` sections from Cargo.toml, returns {"dev", "release", ...custom}
- Functions exported as `cargo._*` for testing

### Modified `debug_bin` Function
- Fetches available profiles from workspace Cargo.toml
- `rust_build_and_debug(name, profile)` now accepts profile parameter
- Constructs correct target path (`target/<profile>/`) and build flags based on profile
- Stores `profile` in session object for rebuild
- `pinned_binary` now stores `{name, profile}` tuple instead of just name
- Selection menu shows all binary+profile combinations with tab-separated alignment:
  ```
  my-app    	(dev)     [pin]
  my-app    	(dev)
  my-app    	(release) [pin]
  my-app    	(release)
  ```

### Modified `rebuild_and_reload` Function
- Shows profile in rebuild notification when available
- Already works correctly via stored `session.build_cmd` and `session.path`

## Files Changed
- `lua/cargo.lua` - Profile helper functions, debug_bin modifications, test exports
- `tests/cargo_spec.lua` - Unit tests for profile helpers (6 new tests)
- `tests/e2e_spec.lua` - E2E tests for profile menu entries (3 new tests)
- `tests/fixtures/test-project/Cargo.toml` - Added custom profiles for testing

## Tests Added

### Unit Tests (`cargo_spec.lua`)
- `_profile_to_target_dir`: maps dev→debug, release→release, custom→custom
- `_profile_to_build_flag`: maps dev→"", release→"--release", custom→"--profile X"
- `_get_available_profiles`: detects dev/release always, parses custom profiles from Cargo.toml

### E2E Tests (`e2e_spec.lua`)
- `should show all profiles in binary selection menu`: Creates temp crate with custom profiles (profiling, bench-debug), mocks `vim.ui.select`, verifies all profiles appear with pin options and binary name
- `should build with correct profile flags`: Verifies flag generation
- `should use correct target directory for profiles`: Verifies path mapping

## Test Results
- All 16 cargo unit tests pass
- All 9 e2e tests pass
