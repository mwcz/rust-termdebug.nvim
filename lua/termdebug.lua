local options = require("options")

local termdebug = {}

-- load and launch termdebug on the given binary, and then move the cursr back
-- to the given win_id, if keep_cursor_in_place is true.
termdebug.start = function(binary_path, original_win_id)
    -- load termdebug if not already loaded
    if vim.fn.exists("*TermDebugSendCommand") == 0 then
        vim.cmd("packadd termdebug")
    end

    vim.cmd("Termdebug " .. vim.fn.fnameescape(binary_path))

    -- swap the positions of the gdb repl and stdout window;
    -- I like having the gdb repl on the top or right
    -- there might be edge cases where this swaps the wrong windows but I tried
    -- it in many split configurations and they all worked as desired.
    if options.current.swap_termdebug_windows then
        vim.cmd("wincmd x")
    end

    for _, cmd in ipairs(options.current.gdb_startup_commands) do
        vim.fn.TermDebugSendCommand(cmd)
    end

    -- optionally move the cursor back to the original window
    if options.current.keep_cursor_in_place then
        vim.defer_fn(function()
            if vim.api.nvim_win_is_valid(original_win_id) then
                vim.api.nvim_set_current_win(original_win_id)
            end
        end, 20) -- 20ms delay
    end
end

-- copy the options.termdebug_config passed into rust-termdebug.nvim setup() to
-- the global termdebug_config, but only if there is no global termdebug_config
-- already.
termdebug.init_termdebug_config = function(options_termdebug_config)
    if not vim.g.termdebug_config then
        vim.g.termdebug_config = options_termdebug_config
    end
end

return termdebug
