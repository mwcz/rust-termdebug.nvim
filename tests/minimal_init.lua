-- Minimal init for running tests
vim.cmd([[set runtimepath=$VIMRUNTIME]])
vim.cmd([[set packpath=/tmp/nvim/site]])

-- Disable netrw to avoid packpath errors
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Get the directory where this file is located
local test_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":p:h")
local plugin_dir = vim.fn.fnamemodify(test_dir, ":h")

-- Change to plugin directory so relative paths work
vim.fn.chdir(plugin_dir)

-- Install plenary if not present
local package_root = "/tmp/nvim/site/pack"
local install_path = package_root .. "/packer/start/plenary.nvim"

if vim.fn.isdirectory(install_path) == 0 then
    print("Installing plenary.nvim...")
    vim.fn.system({
        "git",
        "clone",
        "--depth=1",
        "https://github.com/nvim-lua/plenary.nvim",
        install_path,
    })
end

vim.cmd("packadd plenary.nvim")

-- Add rust-termdebug.nvim to runtime path
vim.opt.runtimepath:prepend(plugin_dir)

-- Make sure lua modules can be required from the plugin
package.path = plugin_dir .. "/lua/?.lua;" .. plugin_dir .. "/lua/?/init.lua;" .. package.path
