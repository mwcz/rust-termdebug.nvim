-- Hash line locator strategy
-- Matches lines by exact content hash (SHA256 of trimmed line)
-- Handles line movement but fails if content changes

local M = {}

M.failure_reason = "hashed line location failed"

-- Hash a trimmed line
local function hash_line(line_content)
    local trimmed = vim.trim(line_content)
    return vim.fn.sha256(trimmed)
end

-- Prepare data for persistence
M.prepare = function(line_content)
    return {
        line_hash = hash_line(line_content),
    }
end

-- Find line in buffer by matching hash
-- Returns 0-indexed line number or nil
M.find = function(bufnr, stored_data, original_line_0indexed)
    if not stored_data or not stored_data.line_hash then
        return nil
    end

    local target_hash = stored_data.line_hash
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local matching_lines = {}

    -- Hash every line and find matches
    for i = 0, line_count - 1 do
        local lines = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)
        if lines and #lines > 0 then
            local line_hash = hash_line(lines[1])
            if line_hash == target_hash then
                -- Exact position match - return immediately
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

    -- Multiple matches: find nearest to original line
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

return M
