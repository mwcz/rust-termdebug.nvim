local gdb = {}

-- automatically go into insert mode when entering the gdb window
gdb.auto_insert = function()
	local gdb_augroup = vim.api.nvim_create_augroup("GdbAutoInsert", { clear = true })

	vim.api.nvim_create_autocmd("WinEnter", {
		group = gdb_augroup,
		pattern = "*/rust-gdb",
		callback = function()
			vim.cmd("startinsert")
		end,
		desc = "Automatically enter insert mode in the GDB REPL window",
	})
end

return gdb
