-- Tests for breakpoints module
-- Run with: nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

describe("breakpoints module", function()
    local breakpoints
    local test_files = {}

    -- Helper to create a temp test file and track it for cleanup
    local function create_test_file(content_lines)
        local file = vim.fn.tempname() .. ".rs"
        vim.fn.writefile(content_lines, file)
        table.insert(test_files, file)
        return file
    end

    -- Helper to ensure cleanup happens even if test fails
    local function cleanup_files()
        for _, file in ipairs(test_files) do
            pcall(vim.fn.delete, file)
        end
        test_files = {}
    end

    before_each(function()
        -- Navigate to test fixture
        vim.cmd("cd tests/fixtures/test-project")

        -- Reload breakpoints module
        package.loaded["breakpoints"] = nil
        breakpoints = require("breakpoints")

        -- Create a test file
        local lines = {
            "fn main() {",
            "    println!(\"Hello, world!\");",
            "    let x = 42;",
            "    let y = x + 1;",
            "    println!(\"y = {}\", y);",
            "}",
        }
        local test_file = create_test_file(lines)

        -- Open the test file in a buffer
        vim.cmd("edit " .. vim.fn.fnameescape(test_file))
    end)

    after_each(function()
        -- Clean up files (using pcall to ensure it runs even if tests fail)
        cleanup_files()

        vim.cmd("cd ../../..")

        -- Delete all breakpoints
        pcall(breakpoints.delete_all)
    end)

    describe("breakpoint creation", function()
        it("should create a breakpoint on current line", function()
            -- Move to line 3
            vim.api.nvim_win_set_cursor(0, { 3, 0 })

            -- Create breakpoint
            breakpoints.create()

            -- Get all breakpoints
            local bps = breakpoints.get_all()

            -- Should have one breakpoint
            assert.equals(1, #bps)
            assert.equals(test_files[1], bps[1].file)
            assert.equals(3, bps[1].line)
        end)

        it("should create multiple breakpoints", function()
            -- Create breakpoint on line 3
            vim.api.nvim_win_set_cursor(0, { 3, 0 })
            breakpoints.create()

            -- Create breakpoint on line 5
            vim.api.nvim_win_set_cursor(0, { 5, 0 })
            breakpoints.create()

            -- Get all breakpoints
            local bps = breakpoints.get_all()

            -- Should have two breakpoints
            assert.equals(2, #bps)

            -- Check lines
            local lines = {}
            for _, bp in ipairs(bps) do
                table.insert(lines, bp.line)
            end
            table.sort(lines)

            assert.same({3, 5}, lines)
        end)

        it("should not create duplicate breakpoint on same line", function()
            -- Move to line 3
            vim.api.nvim_win_set_cursor(0, { 3, 0 })

            -- Create breakpoint twice
            breakpoints.create()
            breakpoints.create()

            -- Get all breakpoints
            local bps = breakpoints.get_all()

            -- Should still have only one breakpoint
            assert.equals(1, #bps)
        end)
    end)

    describe("breakpoint deletion", function()
        it("should delete breakpoint on current line", function()
            -- Create breakpoint on line 3
            vim.api.nvim_win_set_cursor(0, { 3, 0 })
            breakpoints.create()

            -- Verify it was created
            local bps = breakpoints.get_all()
            assert.equals(1, #bps)

            -- Delete it
            breakpoints.delete_curline()

            -- Verify it was deleted
            bps = breakpoints.get_all()
            assert.equals(0, #bps)
        end)

        it("should delete specific breakpoint with delete_at", function()
            -- Create breakpoints on lines 3 and 5
            vim.api.nvim_win_set_cursor(0, { 3, 0 })
            breakpoints.create()
            vim.api.nvim_win_set_cursor(0, { 5, 0 })
            breakpoints.create()

            -- Verify both were created
            local bps = breakpoints.get_all()
            assert.equals(2, #bps)

            -- Delete line 3 breakpoint using delete_at
            local bufnr = vim.api.nvim_get_current_buf()
            local deleted = breakpoints.delete_at(bufnr, 2) -- 0-indexed, so line 3 is index 2

            assert.is_true(deleted)

            -- Verify only one remains
            bps = breakpoints.get_all()
            assert.equals(1, #bps)
            assert.equals(5, bps[1].line)
        end)

        it("should delete all breakpoints", function()
            -- Create multiple breakpoints
            for i = 2, 5 do
                vim.api.nvim_win_set_cursor(0, { i, 0 })
                breakpoints.create()
            end

            -- Verify they were created
            local bps = breakpoints.get_all()
            assert.equals(4, #bps)

            -- Delete all
            breakpoints.delete_all()

            -- Verify all were deleted
            bps = breakpoints.get_all()
            assert.equals(0, #bps)
        end)
    end)

    describe("breakpoint toggle", function()
        it("should toggle breakpoint on and off", function()
            -- Move to line 3
            vim.api.nvim_win_set_cursor(0, { 3, 0 })

            -- Toggle on (create)
            breakpoints.toggle()
            local bps = breakpoints.get_all()
            assert.equals(1, #bps)

            -- Toggle off (delete)
            breakpoints.toggle()
            bps = breakpoints.get_all()
            assert.equals(0, #bps)

            -- Toggle on again
            breakpoints.toggle()
            bps = breakpoints.get_all()
            assert.equals(1, #bps)
        end)
    end)

    describe("breakpoint persistence", function()
        local persist_config = { enabled = true, line_locator = "exact" }

        it("should save and load breakpoints from disk", function()
            -- Enable persistence
            breakpoints.set_persistence(persist_config)

            -- Create some breakpoints
            vim.api.nvim_win_set_cursor(0, { 3, 0 })
            breakpoints.create()
            vim.api.nvim_win_set_cursor(0, { 5, 0 })
            breakpoints.create()

            -- Save to disk
            breakpoints.save_to_disk()

            -- Verify breakpoints were saved
            local bps_before = breakpoints.get_all()
            assert.equals(2, #bps_before)

            -- Simulate a restart by reloading the module
            -- This clears in-memory state without calling delete_all (which would save empty state)
            package.loaded["breakpoints"] = nil
            breakpoints = require("breakpoints")
            breakpoints.set_persistence(persist_config)

            -- Verify in-memory state is empty after reload
            assert.equals(0, #breakpoints.get_all())

            -- Load from disk
            breakpoints.load_from_disk()

            -- Verify breakpoints were restored
            local bps = breakpoints.get_all()
            assert.equals(2, #bps)

            local lines = {}
            for _, bp in ipairs(bps) do
                table.insert(lines, bp.line)
            end
            table.sort(lines)

            assert.same({3, 5}, lines)

            -- Clean up - delete breakpoints and save empty state
            breakpoints.delete_all()

            -- Disable persistence
            breakpoints.set_persistence(nil)
        end)

        it("should handle empty persistence file gracefully", function()
            -- Enable persistence
            breakpoints.set_persistence(persist_config)

            -- Try to load when no file exists
            assert.has_no.errors(function()
                breakpoints.load_from_disk()
            end)

            -- Should have no breakpoints
            assert.equals(0, #breakpoints.get_all())

            -- Disable persistence
            breakpoints.set_persistence(nil)
        end)
    end)

    describe("get_all", function()
        it("should return empty table when no breakpoints exist", function()
            local bps = breakpoints.get_all()
            assert.is_table(bps)
            assert.equals(0, #bps)
        end)

        it("should return all breakpoints with correct structure", function()
            -- Create breakpoints
            vim.api.nvim_win_set_cursor(0, { 3, 0 })
            breakpoints.create()

            local bps = breakpoints.get_all()

            assert.equals(1, #bps)
            assert.is_not_nil(bps[1].file)
            assert.is_number(bps[1].line)
            assert.is_string(bps[1].file)
        end)

        it("should return breakpoints from multiple buffers", function()
            -- Create breakpoint in first buffer
            vim.api.nvim_win_set_cursor(0, { 3, 0 })
            breakpoints.create()

            -- Create another test file
            local lines = {
                "fn test() {",
                "    let a = 1;",
                "    let b = 2;",
                "}",
            }
            local test_file2 = create_test_file(lines)
            vim.cmd("edit " .. vim.fn.fnameescape(test_file2))

            -- Create breakpoint in second buffer
            vim.api.nvim_win_set_cursor(0, { 2, 0 })
            breakpoints.create()

            -- Get all breakpoints
            local bps = breakpoints.get_all()

            -- Should have breakpoints from both files
            assert.equals(2, #bps)

            local files = {}
            for _, bp in ipairs(bps) do
                table.insert(files, bp.file)
            end

            assert.is_true(vim.tbl_contains(files, test_files[1]))
            assert.is_true(vim.tbl_contains(files, test_file2))
        end)
    end)
end)
