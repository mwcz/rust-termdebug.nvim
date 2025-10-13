local termdebug = require("termdebug")

local process = {}

process.debug_attach = function()
    vim.notify("Searching for running processes...", vim.log.levels.INFO)

    -- 1. Get the list of processes directly into a Lua table.
    -- The '--no-headers' flag provides a clean list without the column titles.
    local process_lines = vim.fn.systemlist("ps -eo pid,args --no-headers")

    if not process_lines or #process_lines == 0 then
        vim.notify("Could not find any running processes.", vim.log.levels.WARN)
        return
    end

    -- 2. Use vim.ui.select to present the list to the user.
    vim.ui.select(process_lines, { prompt = "Select process to attach to:" }, function(selected_process)
        -- 3. Handle cancellation.
        if not selected_process then
            vim.notify("Attach cancelled.", vim.log.levels.INFO)
            return
        end

        -- 4. Parse the PID and program path from the selected line.
        local parts = vim.split(vim.trim(selected_process), "%s+", { trimempty = true })
        local pid = parts[1]
        local program_path = parts[2]

        if not pid or not program_path then
            vim.notify("Could not parse PID and program path from selection.", vim.log.levels.ERROR)
            return
        end

        vim.notify("Attaching to PID: " .. pid .. " (" .. program_path .. ")", vim.log.levels.INFO)

        local original_win_id = vim.api.nvim_get_current_win()
        termdebug.start(nil, original_win_id)

        vim.defer_fn(function()
            vim.fn.TermDebugSendCommand("attach " .. pid)
            vim.notify("Attached to process. Use 'continue' in GDB to resume.", vim.log.levels.INFO)
        end, 100)
    end)
end

return process
