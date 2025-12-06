local breakpoints = require("breakpoints")
local cargo = require("cargo")
local commands = require("commands")
local gdb = require("gdb")
local keymaps = require("keymaps")
local scheduler = require("scheduler")
local termdebug = require("termdebug")
local options = require("options")

local rust_termdebug = {
    breakpoints = breakpoints,
    cargo = cargo,
    commands = commands,
    gdb = gdb,
    keymaps = keymaps,
    scheduler = scheduler,
    termdebug = termdebug,
}

rust_termdebug.setup = function(options_in)
    options.init(options_in)

    termdebug.init_termdebug_config(options.current.termdebug_config)

    commands.create()

    if options.current.gdb_auto_insert then
        gdb.auto_insert()
    end

    if options.current.use_default_keymaps then
        keymaps.default()
    end

    if options.current.enable_telescope then
        keymaps.telescope()
    end

    -- Set up breakpoint persistence if enabled
    if options.current.persist_breakpoints then
        breakpoints.set_persistence(true)

        -- Load breakpoints from previous session
        vim.defer_fn(function()
            breakpoints.load_from_disk()
        end, 100) -- Delay to ensure buffers are loaded

        -- Save breakpoints on exit
        vim.api.nvim_create_autocmd("VimLeavePre", {
            callback = function()
                breakpoints.save_to_disk()
            end,
            desc = "Save rust-termdebug breakpoints before exit",
        })
    else
        breakpoints.set_persistence(false)
    end
end

return rust_termdebug
