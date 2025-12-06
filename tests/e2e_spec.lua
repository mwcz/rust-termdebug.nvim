-- End-to-end tests that actually launch termdebug and GDB
--
-- NOTE: These tests require a full terminal environment and use pre-built binaries.
--
-- To run these tests:
--   make test-e2e
--
-- Test coverage:
-- - Launching termdebug with GDB
-- - Creating and verifying breakpoints in GDB
-- - Deleting breakpoints from GDB
-- - Toggling breakpoints
-- - Running to breakpoints and stepping through code
-- - Scheduler lock/unlock functionality

describe("e2e tests", function()
    local breakpoints
    local cargo
    local termdebug
    local scheduler

    -- Helper to wait for a condition with timeout
    local function wait_for(condition, timeout_ms, interval_ms)
        timeout_ms = timeout_ms or 5000
        interval_ms = interval_ms or 100
        local start = vim.loop.now()
        while not condition() and (vim.loop.now() - start) < timeout_ms do
            vim.wait(interval_ms)
        end
        return condition()
    end

    -- Helper to find a buffer by pattern
    local function find_buffer(pattern)
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            local bufname = vim.api.nvim_buf_get_name(bufnr)
            if bufname:match(pattern) then
                return bufnr
            end
        end
        return nil
    end

    -- Helper to get GDB buffer
    local function get_gdb_buffer()
        -- Find the gdb buffer (not the "gdb program" buffer)
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            local bufname = vim.api.nvim_buf_get_name(bufnr)
            -- Match buffers with "gdb" but not "gdb program"
            if bufname:match("gdb") and not bufname:match("#gdb program") then
                return bufnr
            end
        end
        return nil
    end

    -- Helper to send GDB command and wait
    local function send_gdb_command(cmd)
        vim.fn.TermDebugSendCommand(cmd)
        vim.wait(200) -- Give GDB time to process
    end

    -- Helper to get GDB buffer output
    local function get_gdb_output()
        local gdb_buf = get_gdb_buffer()
        if not gdb_buf then
            return nil
        end
        return vim.api.nvim_buf_get_lines(gdb_buf, 0, -1, false)
    end

    -- Helper to check if a string is in GDB output
    local function gdb_output_contains(pattern)
        local output = get_gdb_output()
        if not output then
            return false
        end
        for _, line in ipairs(output) do
            if line:match(pattern) then
                return true
            end
        end
        return false
    end

    before_each(function()
        -- Store the plugin root directory (where minimal_init.lua has already cd'd us)
        -- We need to detect this once at the start
        local current_dir = vim.fn.getcwd()
        local plugin_root

        -- If we're already in test-project, go back to plugin root
        if current_dir:match("test%-project$") then
            plugin_root = vim.fn.fnamemodify(current_dir, ":h:h:h")
            vim.cmd("cd " .. vim.fn.fnameescape(plugin_root))
        else
            plugin_root = current_dir
        end

        -- Reload modules WHILE in plugin root (so lua path works)
        package.loaded["breakpoints"] = nil
        package.loaded["cargo"] = nil
        package.loaded["termdebug"] = nil
        package.loaded["options"] = nil

        local options = require("options")
        -- Initialize options with defaults
        options.init({})

        breakpoints = require("breakpoints")
        cargo = require("cargo")
        termdebug = require("termdebug")
        scheduler = require("scheduler")

        -- NOW navigate to test fixture
        local test_project = plugin_root .. "/tests/fixtures/test-project"
        vim.cmd("cd " .. vim.fn.fnameescape(test_project))
    end)

    after_each(function()
        -- Quit GDB if it's running
        pcall(function()
            vim.fn.TermDebugSendCommand("quit")
            vim.wait(300)
        end)

        -- Clean up all breakpoints (suppress errors)
        pcall(breakpoints.delete_all)

        -- Force close all buffers
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(bufnr) then
                pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
            end
        end

        -- Give everything time to clean up
        vim.wait(500)

        -- Return to plugin root
        local plugin_root = vim.fn.fnamemodify(vim.fn.getcwd(), ":h:h:h")
        pcall(vim.cmd, "cd " .. vim.fn.fnameescape(plugin_root))
    end)

    describe("debugging session", function()
        it("should launch termdebug with rust-gdb", function()
            -- Use pre-built binary (built by make test-e2e setup)
            local binary_path = vim.fn.getcwd() .. "/target/debug/test-project"

            -- Verify binary exists
            assert.equals(1, vim.fn.filereadable(binary_path), "Binary should exist at " .. binary_path)

            -- Open main.rs
            vim.cmd("edit src/main.rs")

            -- Launch termdebug
            termdebug.start(binary_path)

            -- Wait for GDB to start
            local gdb_started = wait_for(function()
                return get_gdb_buffer() ~= nil
            end, 10000)

            assert.is_true(gdb_started, "GDB should have started")

            -- Verify we have a GDB buffer
            local gdb_buf = get_gdb_buffer()
            assert.is_not_nil(gdb_buf)
        end)
    end)

    describe("breakpoints", function()
        it("should create breakpoint and verify in GDB", function()
            local binary_path = vim.fn.getcwd() .. "/target/debug/test-project"

            -- Set breakpoint on line 18 (fibonacci call)
            vim.cmd("edit src/main.rs")
            vim.api.nvim_win_set_cursor(0, { 18, 0 })
            breakpoints.create()

            -- Verify breakpoint in extmarks
            local bps = breakpoints.get_all()
            assert.equals(1, #bps)
            assert.equals(18, bps[1].line)

            -- Launch termdebug
            termdebug.start(binary_path)

            assert.is_true(wait_for(function()
                return get_gdb_buffer() ~= nil
            end, 10000))

            -- Give time for breakpoint restoration
            vim.wait(500)

            -- Verify breakpoint in GDB
            send_gdb_command("info breakpoints")
            vim.wait(500)

            local output = get_gdb_output()
            local found_breakpoint = false
            for _, line in ipairs(output or {}) do
                if line:match("main%.rs:18") then
                    found_breakpoint = true
                    break
                end
            end

            assert.is_true(found_breakpoint, "Breakpoint should appear in GDB")
        end)

        it("should delete all breakpoints from GDB", function()
            local binary_path = vim.fn.getcwd() .. "/target/debug/test-project"

            -- Create multiple breakpoints
            vim.cmd("edit src/main.rs")
            vim.api.nvim_win_set_cursor(0, { 18, 0 })
            breakpoints.create()
            vim.api.nvim_win_set_cursor(0, { 21, 0 })
            breakpoints.create()

            -- Launch termdebug
            termdebug.start(binary_path)
            assert.is_true(wait_for(function()
                return get_gdb_buffer() ~= nil
            end, 10000))
            vim.wait(500)

            -- Delete all breakpoints
            breakpoints.delete_all()
            vim.wait(500)

            -- Verify no breakpoints in GDB
            send_gdb_command("info breakpoints")
            vim.wait(500)

            local output = get_gdb_output()
            local has_no_breakpoints = false
            for _, line in ipairs(output or {}) do
                if line:match("No breakpoints") then
                    has_no_breakpoints = true
                    break
                end
            end

            assert.is_true(has_no_breakpoints, "GDB should report no breakpoints")
        end)

        it("should toggle breakpoint on and off", function()
            vim.cmd("edit src/main.rs")
            vim.api.nvim_win_set_cursor(0, { 18, 0 })

            -- Toggle on
            breakpoints.toggle()
            local bps = breakpoints.get_all()
            assert.equals(1, #bps)

            -- Toggle off
            breakpoints.toggle()
            bps = breakpoints.get_all()
            assert.equals(0, #bps)

            -- Toggle on again
            breakpoints.toggle()
            bps = breakpoints.get_all()
            assert.equals(1, #bps)
        end)
    end)

    describe("stepping through code", function()
        it("should run to breakpoint and step through code", function()
            local binary_path = vim.fn.getcwd() .. "/target/debug/test-project"

            -- Set breakpoint at start of main (line 16)
            vim.cmd("edit src/main.rs")
            vim.api.nvim_win_set_cursor(0, { 16, 0 })
            breakpoints.create()

            -- Launch termdebug
            termdebug.start(binary_path)
            assert.is_true(wait_for(function()
                return get_gdb_buffer() ~= nil
            end, 10000))
            vim.wait(500)

            -- Run to breakpoint
            send_gdb_command("run")
            vim.wait(1500)

            -- Verify we're at line 16
            local output = table.concat(get_gdb_output() or {}, "\n")
            assert.is_not_nil(output:match("16"), "Should stop at line 16")

            -- Step to next line
            send_gdb_command("next")
            vim.wait(500)

            -- Should now be at line 18
            output = table.concat(get_gdb_output() or {}, "\n")
            assert.is_not_nil(output:match("18"), "Should advance to line 18")

            -- Continue execution
            send_gdb_command("continue")
            vim.wait(1000)

            -- Program should complete
            output = table.concat(get_gdb_output() or {}, "\n")
            local has_exited = output:match("exited") ~= nil or output:match("inferior.*exited") ~= nil
            assert.is_true(has_exited, "Program should complete")
        end)
    end)

    describe("scheduler", function()
        it("should lock and unlock scheduler", function()
            local binary_path = vim.fn.getcwd() .. "/target/debug/test-project"

            -- Launch termdebug
            vim.cmd("edit src/main.rs")
            termdebug.start(binary_path)
            assert.is_true(wait_for(function()
                return get_gdb_buffer() ~= nil
            end, 10000))
            vim.wait(500)

            -- Lock scheduler
            scheduler.lock()
            vim.wait(300)

            -- Verify scheduler is locked
            send_gdb_command("show scheduler-locking")
            vim.wait(500)

            local output = table.concat(get_gdb_output() or {}, "\n")
            assert.is_not_nil(output:match("on"), "Scheduler should be locked")

            -- Unlock scheduler
            scheduler.unlock()
            vim.wait(300)

            -- Verify scheduler is unlocked
            send_gdb_command("show scheduler-locking")
            vim.wait(500)

            output = table.concat(get_gdb_output() or {}, "\n")
            assert.is_not_nil(output:match("off"), "Scheduler should be unlocked")
        end)
    end)
end)
