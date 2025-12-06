local breakpoints = require("breakpoints")
local scheduler = require("scheduler")
local cargo = require("cargo")
local termdebug = require("termdebug")

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

    vim.api.nvim_create_user_command("RustDebugHide", termdebug.hide, {
        desc = "Hide termdebug panels",
    })

    vim.api.nvim_create_user_command("RustDebugShow", termdebug.show, {
        desc = "Show termdebug panels",
    })

    vim.api.nvim_create_user_command("RustDebugToggle", termdebug.toggle, {
        desc = "Toggle termdebug panels visibility",
    })

    -- Telescope integration (optional, only if telescope is available)
    vim.api.nvim_create_user_command("RustDebugBreakpoints", function()
        local has_telescope, telescope_integration = pcall(require, "telescope_integration")
        if has_telescope then
            telescope_integration.show_breakpoints()
        else
            vim.notify("Telescope.nvim is not installed", vim.log.levels.WARN)
        end
    end, { desc = "Show breakpoints in Telescope picker" })
end

return commands
