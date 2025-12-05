local M = {}

-- Namespace for our breakpoint extmarks
local ns_id = vim.api.nvim_create_namespace("rust_termdebug_breakpoints")

-- Store breakpoints by buffer: { [bufnr] = { [line] = extmark_id } }
local breakpoint_marks = {}

-- Track which buffers have the deletion handler set up
local buffers_with_handlers = {}

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

-- Check if termdebug is currently running
local function is_termdebug_running()
    return vim.fn.exists("*TermDebugSendCommand") ~= 0 and vim.fn.exists("g:termdebug_running") ~= 0
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

    -- Only create the actual GDB breakpoint if termdebug is running
    if is_termdebug_running() then
        vim.cmd("Break")
    end
end

M.delete_all = function()
    vim.fn.TermDebugSendCommand("d")

    -- Clear all extmarks and clean up handlers
    for bufnr, _ in pairs(breakpoint_marks) do
        if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
        end
        cleanup_buffer_handler(bufnr)
    end
    breakpoint_marks = {}
end

-- clear breakpoints on the current line
M.delete_curline = function()
    vim.cmd("Clear")

    -- Remove the extmark on the current line
    local bufnr = vim.api.nvim_get_current_buf()
    local line = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed

    if breakpoint_marks[bufnr] and breakpoint_marks[bufnr][line] then
        vim.api.nvim_buf_del_extmark(bufnr, ns_id, breakpoint_marks[bufnr][line])
        breakpoint_marks[bufnr][line] = nil
    end
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

return M
