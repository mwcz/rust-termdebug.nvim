local scheduler = {}

scheduler.lock = function()
    vim.fn.TermDebugSendCommand("set scheduler-locking on")
    vim.notify("Scheduler pinned to current thread", vim.log.levels.INFO)
end

scheduler.unlock = function()
    -- Unlock the scheduler to allow debugging all threads again
    vim.fn.TermDebugSendCommand("set scheduler-locking off")
    vim.notify("Scheduler unpinned", vim.log.levels.INFO)
end

return scheduler
