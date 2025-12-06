local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
    return
end

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")

local breakpoints = require("breakpoints")

local M = {}

-- Define a sign for breakpoint preview (matches the breakpoint extmark style)
vim.fn.sign_define("RustDebugBreakpoint", {
    text = "●",
    texthl = "DiagnosticError",
})

-- Show all breakpoints in a Telescope picker
M.show_breakpoints = function(opts)
    opts = opts or {}

    -- Get all breakpoints
    local bp_list = breakpoints.get_all()

    if #bp_list == 0 then
        vim.notify("No breakpoints set", vim.log.levels.INFO)
        return
    end

    -- Create display entries
    local results = {}
    for i, bp in ipairs(bp_list) do
        -- Get just the filename from the full path
        local filename = vim.fn.fnamemodify(bp.file, ":t")
        local dir = vim.fn.fnamemodify(bp.file, ":h:t")

        table.insert(results, {
            index = i,
            file = bp.file,
            line = bp.line,
            display = string.format("%s/%s:%d", dir, filename, bp.line),
            ordinal = bp.file .. ":" .. bp.line,
        })
    end

    pickers
        .new(opts, {
            prompt_title = "Breakpoints",
            finder = finders.new_table({
                results = results,
                entry_maker = function(entry)
                    return {
                        value = entry,
                        display = entry.display,
                        ordinal = entry.ordinal,
                        filename = entry.file,
                        lnum = entry.line,
                    }
                end,
            }),
            sorter = conf.generic_sorter(opts),
            previewer = previewers.new_buffer_previewer({
                title = "Breakpoint Preview",
                get_buffer_by_name = function(_, entry)
                    return entry.filename
                end,
                define_preview = function(self, entry, status)
                    conf.buffer_previewer_maker(entry.filename, self.state.bufnr, {
                        bufname = self.state.bufname,
                        winid = self.state.winid,
                        callback = function(bufnr)
                            -- Create a namespace for our preview highlights
                            local ns = vim.api.nvim_create_namespace("telescope_bp_preview_hl")

                            -- Clear any existing preview breakpoint signs and highlights
                            pcall(vim.fn.sign_unplace, "telescope_bp_preview", { buffer = bufnr })
                            pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns, 0, -1)

                            -- Position cursor on the breakpoint line
                            pcall(vim.api.nvim_win_set_cursor, self.state.winid, { entry.lnum, 0 })

                            -- Center the view on the breakpoint line
                            vim.api.nvim_win_call(self.state.winid, function()
                                vim.cmd("normal! zz")
                            end)

                            -- Highlight the breakpoint line (using our namespace)
                            vim.api.nvim_buf_add_highlight(
                                bufnr,
                                ns,
                                "TelescopePreviewLine",
                                entry.lnum - 1,
                                0,
                                -1
                            )

                            -- Add breakpoint sign to show the icon (only for the selected breakpoint)
                            pcall(vim.fn.sign_place, 0, "telescope_bp_preview", "RustDebugBreakpoint", bufnr, {
                                lnum = entry.lnum,
                            })
                        end,
                    })
                end,
            }),
            attach_mappings = function(prompt_bufnr, map)
                -- Default action: jump to breakpoint
                actions.select_default:replace(function()
                    local selection = action_state.get_selected_entry()
                    actions.close(prompt_bufnr)
                    vim.cmd("edit " .. vim.fn.fnameescape(selection.filename))
                    vim.api.nvim_win_set_cursor(0, { selection.lnum, 0 })
                    vim.cmd("normal! zz")
                end)

                -- ctrl-d: delete breakpoint
                map("i", "<C-d>", function()
                    local selection = action_state.get_selected_entry()
                    if selection then
                        local bufnr = vim.fn.bufnr(selection.filename)

                        -- Load buffer if not already loaded
                        if bufnr == -1 then
                            bufnr = vim.fn.bufadd(selection.filename)
                            vim.fn.bufload(bufnr)
                        end

                        -- Delete the breakpoint (using 0-indexed line)
                        local deleted = breakpoints.delete_at(bufnr, selection.lnum - 1)

                        if deleted then
                            -- Refresh the picker with updated breakpoint list
                            local current_picker = action_state.get_current_picker(prompt_bufnr)
                            current_picker:refresh(
                                finders.new_table({
                                    results = (function()
                                        local updated_bp_list = breakpoints.get_all()
                                        local updated_results = {}
                                        for i, bp in ipairs(updated_bp_list) do
                                            local filename = vim.fn.fnamemodify(bp.file, ":t")
                                            local dir = vim.fn.fnamemodify(bp.file, ":h:t")
                                            table.insert(updated_results, {
                                                index = i,
                                                file = bp.file,
                                                line = bp.line,
                                                display = string.format("%s/%s:%d", dir, filename, bp.line),
                                                ordinal = bp.file .. ":" .. bp.line,
                                            })
                                        end
                                        return updated_results
                                    end)(),
                                    entry_maker = function(entry)
                                        return {
                                            value = entry,
                                            display = entry.display,
                                            ordinal = entry.ordinal,
                                            filename = entry.file,
                                            lnum = entry.line,
                                        }
                                    end,
                                }),
                                { reset_prompt = false }
                            )

                            vim.notify("Deleted breakpoint at " .. selection.display, vim.log.levels.INFO)
                        end
                    end
                end)

                return true
            end,
        })
        :find()
end

return M
