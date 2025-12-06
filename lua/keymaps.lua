local breakpoints = require("breakpoints")
local scheduler = require("scheduler")
local cargo = require("cargo")
local process = require("process")
local termdebug = require("termdebug")

local keymaps = {}

keymaps.default = function()
    vim.keymap.set("n", "<leader>dt", cargo.debug_tests, { desc = "Debug tests", noremap = true, silent = true })
    vim.keymap.set("n", "<leader>ds", cargo.debug_bin, { desc = "Debug binary", noremap = true, silent = true })
    vim.keymap.set("n", "<leader>da", process.debug_attach, { desc = "Debug process", noremap = true, silent = true })
    vim.keymap.set("n", "<leader>de", cargo.debug_example, { desc = "Debug example", noremap = true, silent = true })
    vim.keymap.set("n", "<leader>dn", cargo.debug_benches, { desc = "Debug benchmarks", noremap = true, silent = true })
    vim.keymap.set(
        "n",
        "<leader>dx",
        breakpoints.delete_all,
        { desc = "Delete all breakpoints", noremap = true, silent = true }
    )
    vim.keymap.set("n", "<leader>dp", scheduler.lock, { desc = "Pin thread" })
    vim.keymap.set("n", "<leader>du", cargo.clear_pins, { desc = "Clear pinned selections", noremap = true, silent = true })
    vim.keymap.set("n", "<leader>dv", "<cmd>Var<cr>", { desc = "Show vars pane" })
    vim.keymap.set("n", "<leader>dP", scheduler.unlock, { desc = "Unpin thread" })
    vim.keymap.set("n", "<leader>b", breakpoints.toggle, { desc = "Toggle breakpoint", remap = true, silent = true })
    vim.keymap.set(
        "n",
        "<leader>db",
        breakpoints.delete_curline,
        { desc = "Clear breakpoint", remap = true, silent = true }
    )
    vim.keymap.set("n", "<leader>dh", termdebug.toggle, { desc = "Toggle debug panels", noremap = true, silent = true })
end

keymaps.telescope = function()
    vim.keymap.set("n", "<leader>dl", function()
        local has_telescope, telescope_integration = pcall(require, "telescope_integration")
        if has_telescope then
            telescope_integration.show_breakpoints()
        else
            vim.notify("Telescope.nvim is not installed", vim.log.levels.WARN)
        end
    end, { desc = "List breakpoints (Telescope)", noremap = true, silent = true })
end

return keymaps
