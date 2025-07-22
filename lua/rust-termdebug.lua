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
end

return rust_termdebug
