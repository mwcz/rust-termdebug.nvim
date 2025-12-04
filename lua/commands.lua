local breakpoints = require("breakpoints")
local scheduler = require("scheduler")
local cargo = require("cargo")

local commands = {}

commands.create = function()
    vim.api.nvim_create_user_command("RustDebug", cargo.debug_bin, {
        desc = "Build and debug rust binary",
    })

    vim.api.nvim_create_user_command("RustDebugTests", cargo.debug_tests, {
        desc = "Build and debug rust tests",
    })

    vim.api.nvim_create_user_command("RustDebugBenches", cargo.debug_benches, {
        desc = "Build and debug rust benchmarks",
    })

    vim.api.nvim_create_user_command("RustDebugBreak", breakpoints.create, {
        desc = "Set a breakpoint at current line; same as :Break",
    })

    vim.api.nvim_create_user_command("RustDebugClear", breakpoints.delete_all, {
        desc = "Clear all breakpoints",
    })

    vim.api.nvim_create_user_command("RustDebugReload", cargo.rebuild_and_reload, {
        desc = "Rebuild code and reload binary in active debug session",
    })

    vim.api.nvim_create_user_command("RustDebugPinThread", scheduler.lock, {
        desc = "Lock scheduler; debug current thread",
    })

    vim.api.nvim_create_user_command("RustDebugUnpinThread", scheduler.unlock, {
        desc = "Unlock scheduler; debug all threads",
    })
end

return commands
