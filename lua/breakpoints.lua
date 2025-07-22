local M = {}

M.create = function()
    vim.cmd("Break")
end

M.delete_all = function()
    vim.fn.TermDebugSendCommand("d")
end

-- clear breakpoints on the current line
M.clear_curline = function()
    local file_path = vim.fn.expand("%:p")
    if file_path == "" then
        vim.notify("Current filepath (%:p) was empty string", vim.log.levels.ERROR)
        return
    end

    local line_nr = vim.fn.line(".")

    local command = "clear " .. file_path .. ":" .. line_nr

    vim.fn.TermDebugSendCommand(command)
end

return M
