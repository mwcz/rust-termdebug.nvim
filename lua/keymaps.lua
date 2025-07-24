local breakpoints = require("breakpoints")
local scheduler = require("scheduler")
local cargo = require("cargo")

local keymaps = {}

keymaps.default = function()
    vim.keymap.set("n", "<leader>dt", cargo.debug_tests, { desc = "Debug tests", noremap = true, silent = true })
    vim.keymap.set("n", "<leader>ds", cargo.debug_bin, { desc = "Debug binary", noremap = true, silent = true })
    vim.keymap.set("n", "<leader>de", cargo.debug_example, { desc = "Debug example", noremap = true, silent = true })
    vim.keymap.set(
        "n",
        "<leader>dx",
        breakpoints.delete_all,
        { desc = "Delete all breakpoints", noremap = true, silent = true }
    )
    vim.keymap.set("n", "<leader>dp", scheduler.lock, { desc = "Pin thread" })
    vim.keymap.set("n", "<leader>dv", "<cmd>Var<cr>", { desc = "Show vars pane" })
    vim.keymap.set("n", "<leader>dP", scheduler.unlock, { desc = "Unpin thread" })
    vim.keymap.set("n", "<leader>b", breakpoints.create, { desc = "Set breakpoint", remap = true, silent = true })
    vim.keymap.set(
        "n",
        "<leader>db",
        breakpoints.clear_curline,
        { desc = "Clear breakpoint", remap = true, silent = true }
    )
end

return keymaps
