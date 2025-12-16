-- Jaccard line locator strategy
-- Matches lines by token-based Jaccard similarity with position bonus
-- Handles minor edits like variable renames

local M = {}

M.failure_reason = "no similar line found"

-- Minimum similarity threshold to consider a match
local THRESHOLD = 0.5

-- Tokenize a line into a set of alphanumeric tokens
-- This is the base tokenizer; can be overridden for language-specific behavior
M.tokenize = function(line_content)
    local tokens = {}
    for token in line_content:gmatch("[%w_]+") do
        tokens[token] = true
    end
    return tokens
end

-- Compute Jaccard similarity between two token sets
-- Returns value between 0 and 1
M.similarity = function(tokens1, tokens2)
    local intersection = 0
    local union_set = {}

    for token in pairs(tokens1) do
        union_set[token] = true
        if tokens2[token] then
            intersection = intersection + 1
        end
    end
    for token in pairs(tokens2) do
        union_set[token] = true
    end

    local union_size = 0
    for _ in pairs(union_set) do
        union_size = union_size + 1
    end

    if union_size == 0 then
        return 0
    end

    return intersection / union_size
end

-- Prepare data for persistence
M.prepare = function(line_content)
    return {
        line_content = line_content,
    }
end

-- Find line in buffer by Jaccard similarity
-- Returns 0-indexed line number or nil
M.find = function(bufnr, stored_data, original_line_0indexed)
    if not stored_data or not stored_data.line_content then
        return nil
    end

    local target_tokens = M.tokenize(stored_data.line_content)

    -- Check if target has any tokens
    local has_tokens = false
    for _ in pairs(target_tokens) do
        has_tokens = true
        break
    end
    if not has_tokens then
        return nil
    end

    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local best_line = nil
    local best_score = 0
    local best_distance = math.huge

    for i = 0, line_count - 1 do
        local lines = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)
        if lines and #lines > 0 then
            local line_tokens = M.tokenize(lines[1])
            local sim = M.similarity(target_tokens, line_tokens)

            if sim >= THRESHOLD then
                local distance = math.abs(i - original_line_0indexed)

                -- Prefer higher similarity, then closer position
                if sim > best_score or (sim == best_score and distance < best_distance) then
                    best_line = i
                    best_score = sim
                    best_distance = distance
                end
            end
        end
    end

    return best_line
end

return M
