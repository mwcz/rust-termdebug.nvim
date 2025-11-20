local options = require("options")

local termdebug = {}

-- Restore cursor to original window if keep_cursor_in_place is enabled
local function restore_cursor(original_win_id)
    if options.current.keep_cursor_in_place then
        vim.defer_fn(function()
            if vim.api.nvim_win_is_valid(original_win_id) then
                vim.api.nvim_set_current_win(original_win_id)
            end
        end, 20) -- 20ms delay
    end
end

-- load and launch termdebug on the given binary, and then move the cursr back
-- to the given win_id, if keep_cursor_in_place is true.
termdebug.start = function(binary_path, original_win_id)
    -- load termdebug if not already loaded
    if vim.fn.exists("*TermDebugSendCommand") == 0 then
        vim.cmd("packadd termdebug")
    end

    if binary_path ~= nil then
        vim.cmd("Termdebug " .. vim.fn.fnameescape(binary_path))
    else
        vim.cmd("Termdebug")
    end

    termdebug.adjust_layout()

    for _, cmd in ipairs(options.current.gdb_startup_commands) do
        vim.fn.TermDebugSendCommand(cmd)
    end

    restore_cursor(original_win_id)
end

-- copy the options.termdebug_config passed into rust-termdebug.nvim setup() to
-- the global termdebug_config, but only if there is no global termdebug_config
-- already.
termdebug.init_termdebug_config = function(options_termdebug_config)
    if not vim.g.termdebug_config then
        vim.g.termdebug_config = options_termdebug_config
    end
end

-- Adjust the layout of termdebug windows according to configuration
-- swap the positions of the gdb repl and stdout window;
-- I like having the gdb repl on the top or right
-- there might be edge cases where this swaps the wrong windows but I tried
-- it in many split configurations and they all worked as desired.
termdebug.adjust_layout = function()
    if options.current.swap_termdebug_windows then
        vim.cmd("wincmd x")
    end
end

-- Find all termdebug-related windows (GDB and program output)
local function find_termdebug_windows()
    local termdebug_wins = {}

    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) then
            local buf = vim.api.nvim_win_get_buf(win)
            local bufname = vim.api.nvim_buf_get_name(buf)
            local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf })

            -- Termdebug creates terminal buffers with specific names
            -- The GDB buffer typically contains "gdb" in the name
            -- The program output buffer is also a terminal
            if buftype == "terminal" and (
                    bufname:match("gdb") or
                    bufname:match("debugged program") or
                    vim.api.nvim_buf_get_var(buf, "term_title"):match("gdb") or
                    vim.api.nvim_buf_get_var(buf, "term_title"):match("debugged")
                ) then
                table.insert(termdebug_wins, win)
            end
        end
    end

    return termdebug_wins
end

-- Hide all termdebug panels
termdebug.hide = function()
    local wins = find_termdebug_windows()

    if #wins == 0 then
        vim.notify("No termdebug panels found", vim.log.levels.WARN)
        return
    end

    for _, win in ipairs(wins) do
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_hide(win)
        end
    end

    vim.notify("Termdebug panels hidden", vim.log.levels.INFO)
end

-- Show all termdebug panels
termdebug.show = function()
    local original_win_id = vim.api.nvim_get_current_win()

    -- Find all termdebug buffers that are not currently displayed
    local all_bufs = vim.api.nvim_list_bufs()
    local termdebug_bufs = {}

    for _, buf in ipairs(all_bufs) do
        if vim.api.nvim_buf_is_valid(buf) then
            local bufname = vim.api.nvim_buf_get_name(buf)
            local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf })

            if buftype == "terminal" then
                local ok, term_title = pcall(vim.api.nvim_buf_get_var, buf, "term_title")
                if ok and (term_title:match("gdb") or term_title:match("debugged")) then
                    -- Check if this buffer is already displayed in a window
                    local is_displayed = false
                    for _, win in ipairs(vim.api.nvim_list_wins()) do
                        if vim.api.nvim_win_get_buf(win) == buf then
                            is_displayed = true
                            break
                        end
                    end

                    if not is_displayed then
                        table.insert(termdebug_bufs, buf)
                    end
                end
            end
        end
    end

    if #termdebug_bufs == 0 then
        vim.notify("No hidden termdebug panels found", vim.log.levels.WARN)
        return
    end

    -- Restore the panels in a split layout
    for i, buf in ipairs(termdebug_bufs) do
        if i == 1 then
            vim.cmd("vertical botright sbuffer " .. buf)
        else
            vim.cmd("belowright sbuffer " .. buf)
        end
    end

    termdebug.adjust_layout()

    restore_cursor(original_win_id)

    vim.notify("Termdebug panels shown", vim.log.levels.INFO)
end

-- Toggle visibility of termdebug panels
termdebug.toggle = function()
    local wins = find_termdebug_windows()

    if #wins > 0 then
        termdebug.hide()
    else
        termdebug.show()
    end
end

return termdebug
