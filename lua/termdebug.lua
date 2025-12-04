local options = require("options")

local termdebug = {}

-- Track active debug session for rebuild-reload
-- { type = DebugType.*, name = string, path = string, build_cmd = string? }
local active_debug_session = nil

-- load and launch termdebug on the given binary
-- opts: optional table with { original_win_id, type, name, build_cmd }
termdebug.start = function(binary_path, opts)
    opts = opts or {}

    -- load termdebug if not already loaded
    if vim.fn.exists("*TermDebugSendCommand") == 0 then
        vim.cmd("packadd termdebug")
    end

    if binary_path ~= nil then
        vim.cmd("Termdebug " .. vim.fn.fnameescape(binary_path))
    else
        vim.cmd("Termdebug")
    end

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
    if options.current.keep_cursor_in_place and opts.original_win_id then
        vim.defer_fn(function()
            if vim.api.nvim_win_is_valid(opts.original_win_id) then
                vim.api.nvim_set_current_win(opts.original_win_id)
            end
        end, 20) -- 20ms delay
    end

    -- Track this debug session if type/name provided
    if opts.type and opts.name then
        active_debug_session = {
            type = opts.type,
            name = opts.name,
            path = binary_path,
            build_cmd = opts.build_cmd,
        }
    end
end

-- Get the active debug session info
termdebug.get_active_session = function()
    return active_debug_session
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
