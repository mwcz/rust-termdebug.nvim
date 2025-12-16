-- Tests for options module
-- Run with: nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

describe("options module", function()
    local options

    before_each(function()
        -- Reload options module
        package.loaded["options"] = nil
        options = require("options")
    end)

    describe("default configuration", function()
        it("should have all required default options", function()
            local defaults = options.defaults

            assert.is_not_nil(defaults.gdb_auto_insert)
            assert.is_not_nil(defaults.gdb_startup_commands)
            assert.is_not_nil(defaults.keep_cursor_in_place)
            assert.is_not_nil(defaults.use_default_keymaps)
            assert.is_not_nil(defaults.swap_termdebug_windows)
            assert.is_not_nil(defaults.pin_suffix)
            assert.is_not_nil(defaults.persist_breakpoints)
            assert.is_not_nil(defaults.enable_telescope)
            assert.is_not_nil(defaults.termdebug_config)
        end)

        it("should have correct default values", function()
            local defaults = options.defaults

            assert.is_true(defaults.gdb_auto_insert)
            assert.is_table(defaults.gdb_startup_commands)
            assert.is_true(defaults.keep_cursor_in_place)
            assert.is_true(defaults.use_default_keymaps)
            assert.is_true(defaults.swap_termdebug_windows)
            assert.equals(" [pin]", defaults.pin_suffix)
            assert.is_table(defaults.persist_breakpoints)
            assert.is_false(defaults.persist_breakpoints.enabled)
            assert.equals("exact", defaults.persist_breakpoints.line_locator)
            assert.is_false(defaults.enable_telescope)
        end)

        it("should have valid termdebug_config defaults", function()
            local config = options.defaults.termdebug_config

            assert.equals(1, config.wide)
            assert.equals(0, config.map_K)
            assert.equals(0, config.map_minus)
            assert.equals(0, config.map_plus)
            assert.equals("rust-gdb", config.command)
        end)
    end)

    describe("options.init", function()
        it("should merge user options with defaults", function()
            local user_opts = {
                gdb_auto_insert = false,
                persist_breakpoints = true,
            }

            options.init(user_opts)

            assert.is_false(options.current.gdb_auto_insert)
            -- persist_breakpoints = true should be normalized to table with enabled = true
            assert.is_table(options.current.persist_breakpoints)
            assert.is_true(options.current.persist_breakpoints.enabled)
            assert.equals("exact", options.current.persist_breakpoints.line_locator)
            -- Other defaults should remain
            assert.is_true(options.current.use_default_keymaps)
            assert.equals(" [pin]", options.current.pin_suffix)
        end)

        it("should handle empty user options", function()
            options.init({})

            -- Should equal defaults
            assert.is_true(options.current.gdb_auto_insert)
            assert.is_true(options.current.keep_cursor_in_place)
            assert.is_false(options.current.persist_breakpoints.enabled)
        end)

        it("should handle nil user options by using empty table", function()
            -- vim.tbl_deep_extend doesn't accept nil, so we expect the user to pass {}
            -- This test verifies that {} works as expected
            options.init({})

            -- Should equal defaults
            assert.is_true(options.current.gdb_auto_insert)
            assert.is_true(options.current.keep_cursor_in_place)
        end)

        it("should allow custom pin_suffix", function()
            options.init({ pin_suffix = " 📌" })

            assert.equals(" 📌", options.current.pin_suffix)
        end)

        it("should allow custom gdb_startup_commands", function()
            local cmds = { "set print pretty on", "set pagination off" }
            options.init({ gdb_startup_commands = cmds })

            assert.same(cmds, options.current.gdb_startup_commands)
        end)

        it("should allow custom termdebug_config", function()
            local custom_config = {
                wide = 0,
                command = "gdb",
            }
            options.init({ termdebug_config = custom_config })

            assert.equals(0, options.current.termdebug_config.wide)
            assert.equals("gdb", options.current.termdebug_config.command)
        end)
    end)

    describe("options.current", function()
        it("should be nil before init is called", function()
            -- Before init is called
            package.loaded["options"] = nil
            options = require("options")

            assert.is_nil(options.current)
        end)

        it("should update after init", function()
            options.init({ persist_breakpoints = true })

            assert.is_true(options.current.persist_breakpoints.enabled)
            assert.is_false(options.defaults.persist_breakpoints.enabled)
        end)
    end)

    describe("boolean options", function()
        it("should accept all boolean combinations", function()
            options.init({
                gdb_auto_insert = false,
                keep_cursor_in_place = false,
                use_default_keymaps = false,
                swap_termdebug_windows = false,
                persist_breakpoints = true,
                enable_telescope = true,
            })

            assert.is_false(options.current.gdb_auto_insert)
            assert.is_false(options.current.keep_cursor_in_place)
            assert.is_false(options.current.use_default_keymaps)
            assert.is_false(options.current.swap_termdebug_windows)
            assert.is_true(options.current.persist_breakpoints.enabled)
            assert.is_true(options.current.enable_telescope)
        end)
    end)

    describe("persist_breakpoints options", function()
        it("should normalize true to table with enabled=true", function()
            options.init({ persist_breakpoints = true })

            assert.is_table(options.current.persist_breakpoints)
            assert.is_true(options.current.persist_breakpoints.enabled)
            assert.equals("exact", options.current.persist_breakpoints.line_locator)
        end)

        it("should normalize false to table with enabled=false", function()
            options.init({ persist_breakpoints = false })

            assert.is_table(options.current.persist_breakpoints)
            assert.is_false(options.current.persist_breakpoints.enabled)
            assert.equals("exact", options.current.persist_breakpoints.line_locator)
        end)

        it("should accept table config with custom line_locator", function()
            options.init({
                persist_breakpoints = {
                    enabled = true,
                    line_locator = "hash",
                },
            })

            assert.is_table(options.current.persist_breakpoints)
            assert.is_true(options.current.persist_breakpoints.enabled)
            assert.equals("hash", options.current.persist_breakpoints.line_locator)
        end)

        it("should merge partial table config with defaults", function()
            options.init({
                persist_breakpoints = {
                    enabled = true,
                },
            })

            assert.is_true(options.current.persist_breakpoints.enabled)
            -- line_locator should come from defaults
            assert.equals("exact", options.current.persist_breakpoints.line_locator)
        end)
    end)
end)
