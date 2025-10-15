# rust-termdebug.nvim

This plugin improves the experience of debugging Rust code with vim's [termdebug][termdebug] and GDB.

I wrote it in lua since I don't know vimscript, so it's only compatible with neovim, but it would work in vim as well if ported to vimscript.

## Prerequisites

Install Rust and Cargo through [rustup][rustup]. Reasons for requiring rustup:

 - rustup installs come with `rust-gdb`; a GDB wrapper that includes pretty-printers for many complex Rust types.
 - `rust-gdb` will automatically launch with-printers that match the version of rustc in use for your project, avoiding debugger errors about being unable to print some values.

## Installation

lazy.nvim
```lua
{
    'mwcz/rust-termdebug.nvim',
    ft = { "rust" },
    opts = {}
}
```

(PRs welcome to add further installation examples.)

## Configuration options

Default configuration:

```lua
{
    -- Whether to enter insert mode upon entering the gdb window.
    gdb_auto_insert = true,
    -- Provide a list of commands to run in gdb when it starts up.  It's
    -- better to put startup commands in your gdbinit file instead, but
    -- this is offered for any gdb startup commands that you want to be
    -- specific to vim.
    gdb_startup_commands = {},
    -- After launching gdb, return the cursor to its original location
    -- instead of moving it to the new gdb window; this is useful because
    -- you must launch gdb, then set breakpoints, then return to the gdb
    -- window to issue commands.
    keep_cursor_in_place = true,
    -- Enable default keymaps, or set to `false` to set up your own keymaps.
    use_default_keymaps = true,
    -- Swap the gdb window and the program stdout window.
    swap_termdebug_windows = true,
    -- This is used to configure Vim's built-in g:termdebug_config on
    -- startup. If you already have g:termdebug_config set in your config,
    -- this option will be ignored.
    termdebug_config = {
        wide = 1,
        map_K = 0,
        map_minus = 0,
        map_plus = 0,
        command = "rust-gdb",
    },
}
```

## Keymaps

These are the default keymaps.  

  | Keymap       | Command                      | Action                 | Description                                                                                                        |
  | :---         | :---                         | :---                   | :---                                                                                                               |
  | `<leader>ds` | `cargo.debug_bin`            | Debug binary           | Build and debug a binary in your workspace.                                                                        |
  | `<leader>dt` | `cargo.debug_tests`          | Debug tests            | Build and debug a test suite in your workspace.                                                                    |
  | `<leader>de` | `cargo.debug_example`        | Debug examples         | Build and debug an example in your workspace.                                                                      |
  | `<leader>dn` | `cargo.debug_benches`        | Debug benchmarks       | Build and debug a benchmark in your workspace. See [Debugging benchmarks](#debugging-benchmarks) for setup.        |
  | `<leader>b`  | `breakpoints.create`         | Set breakpoint         | Set a breakpoint on the current line.                                                                              |
  | `<leader>db` | `breakpoints.delete_curline` | Delete breakpoint      | Delete the breakpoint on the current line.                                                                         |
  | `<leader>dx` | `breakpoints.delete_all`     | Delete all breakpoints | Delete all breakpoints.                                                                                            |
  | `<leader>dp` | `scheduler.lock`             | Pin thread             | Locks the GDB scheduler to the current thread, preventing the debugger from jumping between threads when stepping. |
  | `<leader>dP` | `scheduler.unlock`           | Unpin thread           | Unlocks the GDB scheduler.                                                                                         |
  | `<leader>dv` | `:Var`                       | Show simple variables  | Runs `:Var` to inspect the state of _simple_ variables in the current scope.                                       |

If you'd rather customize your keymaps, set `use_default_keymaps = false`.

## Selecting from multiple binaries/tests/examples/benchmarks

When debugging a cargo workspace with multiple targets, you'll be prompted to choose which one to debug. The target corresponding to the file you are currently editing will be moved to the top of the list for convenience.

You can also select any target with the `[pin]` suffix to save it as the default for the current session. The next time you launch the debugger during that session, the pinned target will be used automatically and always recompiled.

- Binaries are listed by their filename.
- Unit tests are listed by their crate name.  Note that you do not choose individual tests as you would with a DAP debugger's "debuggables" list.  To run specific test(s), use `run test_name` within the GDB buffer.
- Examples, benchmarks, and integration tests are listed by their filename (with `.rs` omitted).

## Example workflows

### Debug a Rust binary

 1. Edit a Rust file.
 2. Press `<leader>ds` to start debugging.  If multiple binaries exist, choose the one you want to debug.  The one being edited will appear at the top of the list.
 3. Move to a line of interest and press `<leader>b` to set a breakpoint.
 4. Move into the gdb window and enter `r` to run the program, optionally with args, eg `r --my-cmd-arg`
 5. Use gdb as usual to debug the program.

### Debug Rust tests

 1. Edit a Rust file.
 2. Press `<leader>dt` to debug tests.  If multiple test module binaries exist, choose the one you want to debug.  The one being edited will appear at the top of the list.
 3. Move to a line of interest and press `<leader>b` to set a breakpoint inside the tests.
 4. Move into the gdb window and enter `r` to run all the tests for the chosen module, or use a name filter like you'd pass to `cargo test`, eg `r my_test_name`
 5. Use gdb as usual to debug the test(s).

## Debugging benchmarks

By default, Rust benchmarks are compiled without debug symbols. To enable debugging benchmarks, add this minimal profile configuration to your `Cargo.toml`:

```toml
[profile.bench]
debug = true
```

This enables debug symbols while keeping all other benchmark optimizations intact. Once configured, you can debug benchmarks just like tests:

 1. Edit a benchmark file.
 2. Press `<leader>dn` to debug benchmarks.  If multiple benchmarks exist, choose the one you want to debug.  The one being edited will appear at the top of the list.
 3. Move to a line of interest and press `<leader>b` to set a breakpoint.
 4. Move into the gdb window and enter `r` to run the benchmark, or use a name filter like you'd pass to `cargo bench`, eg `r my_bench_name`
 5. Use gdb as usual to debug the benchmark.

[termdebug]: https://vimhelp.org/terminal.txt.html#terminal-debug
[rustup]: https://rustup.rs/
[gdb]: https://sourceware.org/gdb/
