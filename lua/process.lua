local termdebug = require("termdebug")
local podman = require("podman")

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

    -- 2. Build a map of PIDs to container info efficiently
    -- Only call podman once to get all containers and their PID namespaces
    local pid_to_container = podman.build_pid_to_container_map()

    -- 3. Build display lines with container suffixes
    local display_lines = {}
    local display_to_original = {} -- Maps display line to original line

    for _, line in ipairs(process_lines) do
        local parts = vim.split(vim.trim(line), "%s+", { trimempty = true })
        local pid = parts[1]

        if pid then
            -- Build display line with suffix if in container
            local display_line = line
            local container_info = pid_to_container[pid]

            if container_info then
                display_line = display_line .. podman.format_process_suffix(container_info)
            end

            table.insert(display_lines, display_line)
            display_to_original[display_line] = line
        end
    end

    -- 4. Use vim.ui.select to present the list to the user with larger size
    local select_opts = {
        prompt = "Select process to attach to:",
        kind = "rust-termdebug-process-select",
    }

    -- Add telescope-specific options if telescope is available
    local has_telescope, telescope_themes = pcall(require, "telescope.themes")
    if has_telescope then
        select_opts.telescope = telescope_themes.get_dropdown({
            layout_config = {
                height = 0.8,  -- 80% of screen height
                width = 0.9,   -- 90% of screen width
            },
        })
    end

    vim.ui.select(display_lines, select_opts, function(selected_display)
        -- 4. Handle cancellation.
        if not selected_display then
            vim.notify("Attach cancelled.", vim.log.levels.INFO)
            return
        end

        -- Get the original line (without suffix)
        local selected_process = display_to_original[selected_display]

        -- 5. Parse the PID and program path from the selected line.
        local parts = vim.split(vim.trim(selected_process), "%s+", { trimempty = true })
        local pid = parts[1]
        local program_path = parts[2]

        if not pid or not program_path then
            vim.notify("Could not parse PID and program path from selection.", vim.log.levels.ERROR)
            return
        end

        -- 6. Check if this is a container process
        local container_info = pid_to_container[pid]

        if container_info then
            -- Use podman debugging for container processes
            vim.notify(
                string.format(
                    "Attaching to PID: %s (%s) in container '%s'",
                    pid,
                    program_path,
                    container_info.name
                ),
                vim.log.levels.INFO
            )
            podman.debug_attach_container(pid, container_info, termdebug)
        else
            -- Use normal GDB attach for host processes
            vim.notify("Attaching to PID: " .. pid .. " (" .. program_path .. ")", vim.log.levels.INFO)

            local original_win_id = vim.api.nvim_get_current_win()
            termdebug.start(nil, { original_win_id = original_win_id })

            vim.defer_fn(function()
                vim.fn.TermDebugSendCommand("attach " .. pid)
                vim.notify("Attached to process. Use 'continue' in GDB to resume.", vim.log.levels.INFO)
            end, 100)
        end
    end)
end

return process
