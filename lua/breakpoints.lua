local M = {}

-- Namespace for our breakpoint extmarks
local ns_id = vim.api.nvim_create_namespace("rust_termdebug_breakpoints")

-- Store breakpoints by buffer: { [bufnr] = { [line] = extmark_id } }
local breakpoint_marks = {}

-- Track which buffers have the deletion handler set up
local buffers_with_handlers = {}

-- Persistence settings
local persistence_enabled = false

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
    if not persistence_enabled then
        return
    end

    local breakpoints_to_save = {}

    -- Collect all breakpoint locations from extmarks
    for bufnr, marks in pairs(breakpoint_marks) do
        if vim.api.nvim_buf_is_valid(bufnr) then
            local bufname = vim.api.nvim_buf_get_name(bufnr)
            -- Only save breakpoints for named buffers (files on disk)
            if bufname ~= "" then
                for _, extmark_id in pairs(marks) do
                    local mark = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, extmark_id, {})
                    if mark and #mark > 0 then
                        table.insert(breakpoints_to_save, {
                            file = bufname,
                            line = mark[1] + 1, -- Convert to 1-indexed
                        })
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

-- Load breakpoints from disk and create extmarks
M.load_from_disk = function()
    if not persistence_enabled then
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

    -- Create extmarks for each saved breakpoint
    for _, bp in ipairs(breakpoints) do
        -- Check if the file exists
        if vim.fn.filereadable(bp.file) == 1 then
            -- Load the buffer if it's not already loaded
            local bufnr = vim.fn.bufnr(bp.file)
            if bufnr == -1 then
                bufnr = vim.fn.bufadd(bp.file)
            end

            -- Initialize buffer tracking if needed
            if not breakpoint_marks[bufnr] then
                breakpoint_marks[bufnr] = {}
            end

            -- Set up deletion handler for this buffer
            setup_buffer_deletion_handler(bufnr)

            -- Create extmark (0-indexed line)
            local line = bp.line - 1
            local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, {
                sign_text = "●",
                sign_hl_group = "DiagnosticError",
            })

            breakpoint_marks[bufnr][line] = extmark_id
        end
    end

    if #breakpoints > 0 then
        vim.notify("Loaded " .. #breakpoints .. " breakpoint(s) from previous session", vim.log.levels.INFO)
    end
end

-- Enable or disable breakpoint persistence
M.set_persistence = function(enabled)
    persistence_enabled = enabled
end

return M
