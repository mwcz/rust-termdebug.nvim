-- Exact line locator strategy
-- Restores breakpoints at their saved line numbers
-- Fails if line number is out of range

local M = {}

M.failure_reason = "out of range"

-- Prepare data for persistence (exact doesn't need extra data)
M.prepare = function(_line_content)
    return nil
end

-- Find line in buffer
-- Returns 0-indexed line number or nil
M.find = function(bufnr, _stored_data, original_line_0indexed)
    local line_count = vim.api.nvim_buf_line_count(bufnr)

    if original_line_0indexed >= line_count then
        return nil
    end

    return original_line_0indexed
end

return M
