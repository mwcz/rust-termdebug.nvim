local options = {
    defaults = {
        -- whether to enter insert mode upon entering the gdb window
        gdb_auto_insert = true,
        -- provide a list of commands to run in gdb when it starts up (recommend putting these in your gdbinit, but this is offered in case you want some startup commands specific to vim)
        gdb_startup_commands = {},
        -- after launching gdb, return the cursor to its original location instead of leaving it in the gdb window
        keep_cursor_in_place = true,
        -- enable or disable the default keymaps
        use_default_keymaps = true,
        -- swap the gdb window and the program stdout window
        swap_termdebug_windows = true,
        -- you may optionally provide a termdebug_config here as a convenience, but you may instead set up termdebug_config as described in `:help termdebug_config`
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
