local M = {}

-- Namespace for our breakpoint extmarks
local ns_id = vim.api.nvim_create_namespace("rust_termdebug_breakpoints")

-- Store breakpoints by buffer: { [bufnr] = { [line] = extmark_id } }
local breakpoint_marks = {}

-- Track which buffers have the deletion handler set up
local buffers_with_handlers = {}

-- Persistence settings (nil = disabled, table = config with line_locator, etc.)
local persistence_config = nil

-- Helper to get a shortened path for user messages
local function short_path(filepath)
    local cwd = vim.fn.getcwd()
    if filepath:sub(1, #cwd) == cwd then
        return filepath:sub(#cwd + 2) -- +2 to skip the trailing slash
    end
    return vim.fn.fnamemodify(filepath, ":~")
end

-- Helper to hash a trimmed line for content-based matching
local function hash_line(line_content)
    local trimmed = vim.trim(line_content)
    -- Use a simple hash: we just need consistency, not cryptographic security
    -- vim.fn.sha256 returns a hex string
    return vim.fn.sha256(trimmed)
end

-- Get the workspace-specific persistence file path
local function get_persistence_file()
    local workspace_root

    -- Try to get the cargo workspace root
    local metadata_json = vim.fn.system("cargo metadata --no-deps --format-version=1 2>/dev/null")
    if vim.v.shell_error == 0 then
        local ok, metadata = pcall(vim.json.decode, metadata_json)
        if ok and metadata and metadata.workspace_root then
            workspace_root = metadata.workspace_root
        end
    end

    -- Fallback to current directory if not in a cargo workspace
    if not workspace_root then
        workspace_root = vim.fn.getcwd()
    end

    -- Create .rust-termdebug.nvim directory if it doesn't exist
    local dir = workspace_root .. "/.rust-termdebug.nvim"
    if vim.fn.isdirectory(dir) == 0 then
        vim.fn.mkdir(dir, "p")
    end

    return dir .. "/breakpoints.json"
end

-- Set up buffer-local autocmd to clean up extmarks when lines are deleted
local function setup_buffer_deletion_handler(bufnr)
    if buffers_with_handlers[bufnr] then
        return -- Already set up for this buffer
    end

    local augroup = vim.api.nvim_create_augroup("RustTermdebugBreakpoints_" .. bufnr, { clear = true })

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        group = augroup,
        buffer = bufnr,
        callback = function()
            if not breakpoint_marks[bufnr] then
                return
            end

            -- Check each tracked breakpoint to see if its extmark still exists
            local marks_to_remove = {}
            for line, extmark_id in pairs(breakpoint_marks[bufnr]) do
                local mark = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, extmark_id, {})
                -- If the extmark doesn't exist anymore, mark it for removal
                if not mark or #mark == 0 then
                    table.insert(marks_to_remove, line)
                end
            end

            -- Remove tracked breakpoints that no longer have extmarks
            for _, line in ipairs(marks_to_remove) do
                breakpoint_marks[bufnr][line] = nil
            end

            -- If no more breakpoints in this buffer, clean up the autocmd
            if next(breakpoint_marks[bufnr]) == nil then
                vim.api.nvim_del_augroup_by_name("RustTermdebugBreakpoints_" .. bufnr)
                buffers_with_handlers[bufnr] = nil
                breakpoint_marks[bufnr] = nil
            end
        end,
    })

    -- Save persistence when file is written (extmarks may have moved due to edits)
    vim.api.nvim_create_autocmd("BufWritePost", {
        group = augroup,
        buffer = bufnr,
        callback = function()
            if breakpoint_marks[bufnr] and persistence_config then
                M.save_to_disk()
            end
        end,
    })

    buffers_with_handlers[bufnr] = true
end

-- Clean up autocmd for a specific buffer
local function cleanup_buffer_handler(bufnr)
    if buffers_with_handlers[bufnr] then
        pcall(vim.api.nvim_del_augroup_by_name, "RustTermdebugBreakpoints_" .. bufnr)
        buffers_with_handlers[bufnr] = nil
    end
end

-- Create a breakpoint and track it with an extmark
M.create = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local line = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed

    -- Initialize buffer tracking if needed
    if not breakpoint_marks[bufnr] then
        breakpoint_marks[bufnr] = {}
    end

    -- Set up deletion handler for this buffer if not already done
    setup_buffer_deletion_handler(bufnr)

    -- Create an extmark at this location
    local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, {
        sign_text = "●",
        sign_hl_group = "DiagnosticError",
    })

    breakpoint_marks[bufnr][line] = extmark_id

    -- Try to create the actual GDB breakpoint if termdebug is running
    -- Use pcall to avoid errors if termdebug isn't active
    pcall(vim.cmd, "Break")

    -- Save to disk immediately
    M.save_to_disk()
end

M.delete_all = function()
    -- Try to delete in GDB if termdebug is running
    pcall(vim.fn.TermDebugSendCommand, "d")

    -- Clear all extmarks and clean up handlers
    for bufnr, _ in pairs(breakpoint_marks) do
        if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
        end
        cleanup_buffer_handler(bufnr)
    end
    breakpoint_marks = {}

    -- Save to disk immediately
    M.save_to_disk()
end

-- clear breakpoints on the current line
M.delete_curline = function()
    -- Try to delete in GDB if termdebug is running
    pcall(vim.cmd, "Clear")

    -- Remove the extmark on the current line
    local bufnr = vim.api.nvim_get_current_buf()
    local line = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed

    if breakpoint_marks[bufnr] and breakpoint_marks[bufnr][line] then
        vim.api.nvim_buf_del_extmark(bufnr, ns_id, breakpoint_marks[bufnr][line])
        breakpoint_marks[bufnr][line] = nil
    end

    -- Save to disk immediately
    M.save_to_disk()
end

-- Delete breakpoint at a specific buffer and line (0-indexed)
M.delete_at = function(bufnr, line)
    if breakpoint_marks[bufnr] and breakpoint_marks[bufnr][line] then
        -- Delete the extmark
        vim.api.nvim_buf_del_extmark(bufnr, ns_id, breakpoint_marks[bufnr][line])
        breakpoint_marks[bufnr][line] = nil

        -- Try to delete in GDB if termdebug is running
        -- We need to find the GDB breakpoint number for this location
        local filename = vim.api.nvim_buf_get_name(bufnr)
        local gdb_line = line + 1 -- GDB uses 1-indexed lines
        pcall(vim.fn.TermDebugSendCommand, string.format("clear %s:%d", filename, gdb_line))

        -- Save to disk immediately
        M.save_to_disk()
        return true
    end
    return false
end

-- Toggle breakpoint on the current line
M.toggle = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local line = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed

    -- Initialize buffer tracking if needed
    if not breakpoint_marks[bufnr] then
        breakpoint_marks[bufnr] = {}
    end

    -- Check if there's already a breakpoint on this line
    if breakpoint_marks[bufnr][line] then
        M.delete_curline()
    else
        M.create()
    end
end

-- Get all breakpoint locations tracked by extmarks
M.get_all = function()
    local breakpoints = {}

    for bufnr, marks in pairs(breakpoint_marks) do
        if vim.api.nvim_buf_is_valid(bufnr) then
            local bufname = vim.api.nvim_buf_get_name(bufnr)
            for _, extmark_id in pairs(marks) do
                local mark = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, extmark_id, {})
                if mark and #mark > 0 then
                    table.insert(breakpoints, {
                        file = bufname,
                        line = mark[1] + 1, -- Convert to 1-indexed
                    })
                end
            end
        end
    end

    return breakpoints
end

-- Restore all breakpoints in GDB from extmarks
M.restore_all = function()
    local breakpoints = M.get_all()

    if #breakpoints == 0 then
        return
    end

    for _, bp in ipairs(breakpoints) do
        local cmd = string.format("break %s:%d", bp.file, bp.line)
        vim.fn.TermDebugSendCommand(cmd)
    end

    vim.notify("Restored " .. #breakpoints .. " breakpoint(s)", vim.log.levels.INFO)
end

-- Save breakpoints to disk for persistence across sessions
M.save_to_disk = function()
    if not persistence_config then
        return
    end

    local breakpoints_to_save = {}
    local use_hash = persistence_config.line_locator == "hash"

    -- Collect all breakpoint locations from extmarks
    for bufnr, marks in pairs(breakpoint_marks) do
        if vim.api.nvim_buf_is_valid(bufnr) then
            local bufname = vim.api.nvim_buf_get_name(bufnr)
            -- Only save breakpoints for named buffers (files on disk)
            if bufname ~= "" then
                -- Load buffer if needed for hash strategy
                if use_hash and not vim.api.nvim_buf_is_loaded(bufnr) then
                    vim.fn.bufload(bufnr)
                end

                for _, extmark_id in pairs(marks) do
                    local mark = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, extmark_id, {})
                    if mark and #mark > 0 then
                        local line_1indexed = mark[1] + 1
                        local bp_entry = {
                            file = bufname,
                            line = line_1indexed,
                        }

                        -- Store line hash if using hash strategy
                        if use_hash then
                            local lines = vim.api.nvim_buf_get_lines(bufnr, mark[1], mark[1] + 1, false)
                            if lines and #lines > 0 then
                                bp_entry.line_hash = hash_line(lines[1])
                            end
                        end

                        table.insert(breakpoints_to_save, bp_entry)
                    end
                end
            end
        end
    end

    -- Write to file
    local file = io.open(get_persistence_file(), "w")
    if file then
        file:write(vim.json.encode(breakpoints_to_save))
        file:close()
    end
end

-- Find line by hash matching, returning 0-indexed line or nil
local function find_line_by_hash(bufnr, target_hash, original_line_0indexed)
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local matching_lines = {}

    -- Hash every line in the buffer and find matches
    for i = 0, line_count - 1 do
        local lines = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)
        if lines and #lines > 0 then
            local line_hash = hash_line(lines[1])
            if line_hash == target_hash then
                -- If this is an exact position match, return immediately
                if i == original_line_0indexed then
                    return i
                end
                table.insert(matching_lines, i)
            end
        end
    end

    if #matching_lines == 0 then
        return nil
    end

    if #matching_lines == 1 then
        return matching_lines[1]
    end

    -- Multiple matches: find the one nearest to the original line
    local best_line = matching_lines[1]
    local best_distance = math.abs(matching_lines[1] - original_line_0indexed)
    for _, line in ipairs(matching_lines) do
        local distance = math.abs(line - original_line_0indexed)
        if distance < best_distance then
            best_line = line
            best_distance = distance
        end
    end
    return best_line
end

-- Load breakpoints from disk and create extmarks
M.load_from_disk = function()
    if not persistence_config then
        return
    end

    local file = io.open(get_persistence_file(), "r")
    if not file then
        return
    end

    local content = file:read("*a")
    file:close()

    if content == "" then
        return
    end

    local ok, breakpoints = pcall(vim.json.decode, content)
    if not ok or not breakpoints then
        return
    end

    local use_hash = persistence_config.line_locator == "hash"
    local restored_count = 0
    local skipped_messages = {}

    -- Create extmarks for each saved breakpoint
    for _, bp in ipairs(breakpoints) do
        local short_file = short_path(bp.file)
        local bp_desc = string.format("%s:%d", short_file, bp.line)

        -- Check if the file exists
        if vim.fn.filereadable(bp.file) ~= 1 then
            table.insert(skipped_messages, string.format("breakpoint %s invalid: file missing", bp_desc))
        else
            -- Load the buffer if it's not already loaded
            local bufnr = vim.fn.bufnr(bp.file)
            if bufnr == -1 then
                bufnr = vim.fn.bufadd(bp.file)
            end
            -- Ensure buffer is loaded so we can query line count
            vim.fn.bufload(bufnr)

            local line_count = vim.api.nvim_buf_line_count(bufnr)
            local target_line = bp.line - 1 -- Convert to 0-indexed

            -- Determine the actual line to use
            local actual_line = nil

            if use_hash and bp.line_hash then
                -- Hash strategy: find matching line by content
                actual_line = find_line_by_hash(bufnr, bp.line_hash, target_line)
                if not actual_line then
                    table.insert(
                        skipped_messages,
                        string.format("breakpoint %s invalid: hashed line location failed", bp_desc)
                    )
                end
            else
                -- Exact strategy: validate line is in range
                if target_line >= line_count then
                    table.insert(skipped_messages, string.format("breakpoint %s invalid: out of range", bp_desc))
                else
                    actual_line = target_line
                end
            end

            -- Create the extmark if we found a valid line
            if actual_line then
                -- Initialize buffer tracking if needed
                if not breakpoint_marks[bufnr] then
                    breakpoint_marks[bufnr] = {}
                end

                -- Set up deletion handler for this buffer
                setup_buffer_deletion_handler(bufnr)

                -- Create extmark
                local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, actual_line, 0, {
                    sign_text = "●",
                    sign_hl_group = "DiagnosticError",
                })

                breakpoint_marks[bufnr][actual_line] = extmark_id
                restored_count = restored_count + 1
            end
        end
    end

    -- Report results
    if #skipped_messages > 0 then
        for _, msg in ipairs(skipped_messages) do
            vim.notify(msg, vim.log.levels.WARN)
        end
    end

    if restored_count > 0 or #skipped_messages > 0 then
        local msg = string.format("Restored %d breakpoint(s)", restored_count)
        if #skipped_messages > 0 then
            msg = msg .. string.format(", %d failed", #skipped_messages)
        end
        vim.notify(msg, vim.log.levels.INFO)
    end
end

-- Enable or disable breakpoint persistence
-- @param config table|nil - persistence config with line_locator, or nil to disable
M.set_persistence = function(config)
    persistence_config = config
end

return M
