# rust-termdebug.nvim

This is a plugin I slapped together to make working with vim's [termdebug][termdebug] on Rust projects.

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
	-- Provide a list of commands to run in gdb when it starts up (recommend putting the commands in your gdbinit instead, but this is offered for gdb startup commands specific to vim).
	gdb_startup_commands = {},
	-- After launching gdb, return the cursor to its original location instead of moving it to the new gdb window; this is useful because you must launch gdb, then set breakpoints, then return to the gdb window to issue commands.
	keep_cursor_in_place = true,
	-- Enable default keymaps, or set to `false` to set up your own keymaps.
	use_default_keymaps = true,
	-- Swap the gdb window and the program stdout window.
    swap_termdebug_windows = true,
	-- This is used to configure Vim's built-in g:termdebug_config on startup. If you already have g:termdebug_config set in your config, this option will be ignored.
	termdebug_config = {
		wide = 1,
		map_K = 0,
		map_minus = 0,
		map_plus = 0,
		command = "rust-gdb",
	},
}
```

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


[termdebug]: https://vimhelp.org/terminal.txt.html#terminal-debug
[rustup]: https://rustup.rs/
[gdb]: https://sourceware.org/gdb/
