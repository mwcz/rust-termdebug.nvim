local options = {
    defaults = {
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
    },
}

options.init = function(options_in)
    options.current = vim.tbl_deep_extend("force", options.defaults, options_in)
end

return options
