-- Line locator strategies for breakpoint persistence
-- Each strategy implements:
--   prepare(line_content) -> data to store in persistence file
--   find(bufnr, stored_data, original_line_0indexed) -> 0-indexed line or nil
--   failure_reason -> string describing why a match failed

local M = {}

-- Registry of available strategies
local strategies = {}

-- Register a strategy
M.register = function(name, strategy)
    strategies[name] = strategy
end

-- Get a strategy by name
M.get = function(name)
    return strategies[name]
end

-- List available strategy names
M.available = function()
    local names = {}
    for name in pairs(strategies) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

-- Load built-in strategies
local function load_builtin_strategies()
    M.register("exact", require("line_locators.exact"))
    M.register("hash", require("line_locators.hash"))
    M.register("jaccard", require("line_locators.jaccard"))
end

load_builtin_strategies()

return M
