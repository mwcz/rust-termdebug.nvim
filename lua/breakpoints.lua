local M = {}

M.create = function()
    vim.cmd("Break")
end

M.delete_all = function()
    vim.fn.TermDebugSendCommand("d")
end

-- clear breakpoints on the current line
M.delete_curline = function()
    vim.cmd("Clear")
end

return M
