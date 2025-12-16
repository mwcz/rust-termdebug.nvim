-- Integration tests for breakpoint persistence across file edits
-- These tests simulate real-world scenarios like git branch switching

describe("breakpoint persistence integration", function()
    local breakpoints
    local test_dir
    local main_rs_path
    local persistence_file

    -- Original main.rs content
    local original_content = {
        "fn main() {",
        "    println!(\"Line 2\");",
        "    let x = 42;",
        "    let y = x + 1;",
        "    println!(\"y = {}\", y);",
        "    let z = y * 2;",
        "    println!(\"z = {}\", z);",
        "}",
    }

    -- Create a test cargo project in temp directory
    local function setup_cargo_project()
        test_dir = vim.fn.tempname()
        vim.fn.mkdir(test_dir, "p")

        -- Create cargo project structure
        local src_dir = test_dir .. "/src"
        vim.fn.mkdir(src_dir, "p")

        -- Create Cargo.toml
        local cargo_toml = {
            "[package]",
            'name = "test-persistence"',
            'version = "0.1.0"',
            'edition = "2021"',
        }
        vim.fn.writefile(cargo_toml, test_dir .. "/Cargo.toml")

        -- Create main.rs
        main_rs_path = src_dir .. "/main.rs"
        vim.fn.writefile(original_content, main_rs_path)

        -- Create persistence directory
        local persist_dir = test_dir .. "/.rust-termdebug.nvim"
        vim.fn.mkdir(persist_dir, "p")
        persistence_file = persist_dir .. "/breakpoints.json"
    end

    -- Clean up test directory
    local function cleanup()
        if test_dir and vim.fn.isdirectory(test_dir) == 1 then
            vim.fn.delete(test_dir, "rf")
        end
    end

    before_each(function()
        -- Set up fresh project
        setup_cargo_project()

        -- Reload breakpoints module
        package.loaded["breakpoints"] = nil
        breakpoints = require("breakpoints")

        -- Change to test directory (for persistence file detection)
        vim.cmd("cd " .. vim.fn.fnameescape(test_dir))
    end)

    after_each(function()
        -- Clean up breakpoints
        pcall(breakpoints.delete_all)
        breakpoints.set_persistence(nil)

        -- Close all buffers
        vim.cmd("bufdo bwipeout!")

        -- Return to original directory
        vim.cmd("cd -")

        -- Remove test directory
        cleanup()
    end)

    describe("exact line_locator", function()
        local persist_config = { enabled = true, line_locator = "exact" }

        it("should restore breakpoints when file unchanged", function()
            breakpoints.set_persistence(persist_config)

            -- Open file and set breakpoints
            vim.cmd("edit " .. vim.fn.fnameescape(main_rs_path))
            vim.api.nvim_win_set_cursor(0, { 3, 0 }) -- let x = 42;
            breakpoints.create()
            vim.api.nvim_win_set_cursor(0, { 5, 0 }) -- println!("y = {}", y);
            breakpoints.create()

            -- Save and close
            breakpoints.save_to_disk()
            vim.cmd("bwipeout!")

            -- Reload module (simulates nvim restart)
            package.loaded["breakpoints"] = nil
            breakpoints = require("breakpoints")
            breakpoints.set_persistence(persist_config)

            -- Load from disk
            breakpoints.load_from_disk()

            -- Verify breakpoints restored
            local bps = breakpoints.get_all()
            assert.equals(2, #bps)

            local lines = {}
            for _, bp in ipairs(bps) do
                table.insert(lines, bp.line)
            end
            table.sort(lines)
            assert.same({ 3, 5 }, lines)
        end)

        it("should skip breakpoint when line out of range after file truncation", function()
            breakpoints.set_persistence(persist_config)

            -- Open file and set breakpoint on line 7
            vim.cmd("edit " .. vim.fn.fnameescape(main_rs_path))
            vim.api.nvim_win_set_cursor(0, { 7, 0 }) -- println!("z = {}", z);
            breakpoints.create()

            -- Save
            breakpoints.save_to_disk()
            vim.cmd("bwipeout!")

            -- Truncate file OUTSIDE vim (simulate git checkout)
            local truncated_content = {
                "fn main() {",
                "    println!(\"short\");",
                "}",
            }
            vim.fn.writefile(truncated_content, main_rs_path)

            -- Reload module
            package.loaded["breakpoints"] = nil
            breakpoints = require("breakpoints")
            breakpoints.set_persistence(persist_config)

            -- Load from disk - should not throw error
            assert.has_no.errors(function()
                breakpoints.load_from_disk()
            end)

            -- Breakpoint should be skipped (line 7 doesn't exist anymore)
            local bps = breakpoints.get_all()
            assert.equals(0, #bps)
        end)

        it("should skip breakpoint when file deleted", function()
            breakpoints.set_persistence(persist_config)

            -- Open file and set breakpoint
            vim.cmd("edit " .. vim.fn.fnameescape(main_rs_path))
            vim.api.nvim_win_set_cursor(0, { 3, 0 })
            breakpoints.create()

            -- Save
            breakpoints.save_to_disk()
            vim.cmd("bwipeout!")

            -- Delete file OUTSIDE vim
            vim.fn.delete(main_rs_path)

            -- Reload module
            package.loaded["breakpoints"] = nil
            breakpoints = require("breakpoints")
            breakpoints.set_persistence(persist_config)

            -- Load from disk - should not throw error
            assert.has_no.errors(function()
                breakpoints.load_from_disk()
            end)

            -- Breakpoint should be skipped
            local bps = breakpoints.get_all()
            assert.equals(0, #bps)
        end)
    end)

    describe("hash line_locator", function()
        local persist_config = { enabled = true, line_locator = "hash" }

        it("should restore breakpoints when file unchanged", function()
            breakpoints.set_persistence(persist_config)

            -- Open file and set breakpoints
            vim.cmd("edit " .. vim.fn.fnameescape(main_rs_path))
            vim.api.nvim_win_set_cursor(0, { 3, 0 }) -- let x = 42;
            breakpoints.create()

            -- Save and close
            breakpoints.save_to_disk()
            vim.cmd("bwipeout!")

            -- Reload module
            package.loaded["breakpoints"] = nil
            breakpoints = require("breakpoints")
            breakpoints.set_persistence(persist_config)

            -- Load from disk
            breakpoints.load_from_disk()

            -- Verify breakpoint restored at same line
            local bps = breakpoints.get_all()
            assert.equals(1, #bps)
            assert.equals(3, bps[1].line)
        end)

        it("should relocate breakpoint when lines inserted before it", function()
            breakpoints.set_persistence(persist_config)

            -- Open file and set breakpoint on "let x = 42;"
            vim.cmd("edit " .. vim.fn.fnameescape(main_rs_path))
            vim.api.nvim_win_set_cursor(0, { 3, 0 })
            breakpoints.create()

            -- Save
            breakpoints.save_to_disk()
            vim.cmd("bwipeout!")

            -- Insert lines at the top OUTSIDE vim
            local modified_content = {
                "// New comment line 1",
                "// New comment line 2",
                "fn main() {",
                "    println!(\"Line 2\");",
                "    let x = 42;", -- Now at line 5 instead of line 3
                "    let y = x + 1;",
                "    println!(\"y = {}\", y);",
                "    let z = y * 2;",
                "    println!(\"z = {}\", z);",
                "}",
            }
            vim.fn.writefile(modified_content, main_rs_path)

            -- Reload module
            package.loaded["breakpoints"] = nil
            breakpoints = require("breakpoints")
            breakpoints.set_persistence(persist_config)

            -- Load from disk
            breakpoints.load_from_disk()

            -- Breakpoint should be at new line 5 (where "let x = 42;" now lives)
            local bps = breakpoints.get_all()
            assert.equals(1, #bps)
            assert.equals(5, bps[1].line)
        end)

        it("should prefer earlier match when equidistant duplicates exist", function()
            breakpoints.set_persistence(persist_config)

            -- Open file and set breakpoint on line 3
            vim.cmd("edit " .. vim.fn.fnameescape(main_rs_path))
            vim.api.nvim_win_set_cursor(0, { 3, 0 }) -- let x = 42;
            breakpoints.create()

            -- Save
            breakpoints.save_to_disk()
            vim.cmd("bwipeout!")

            -- Create file with duplicate lines OUTSIDE vim
            -- Lines 2 and 4 are equidistant (distance=1) from original line 3
            local modified_content = {
                "fn main() {",
                "    let x = 42;", -- Line 2 - duplicate (distance 1)
                "    println!(\"between\");",
                "    let x = 42;", -- Line 4 - duplicate (distance 1)
                "    println!(\"after\");",
                "    let x = 42;", -- Line 6 - duplicate (distance 3)
                "}",
            }
            vim.fn.writefile(modified_content, main_rs_path)

            -- Reload module
            package.loaded["breakpoints"] = nil
            breakpoints = require("breakpoints")
            breakpoints.set_persistence(persist_config)

            -- Load from disk
            breakpoints.load_from_disk()

            -- When equidistant, algorithm selects the earlier match (line 2)
            local bps = breakpoints.get_all()
            assert.equals(1, #bps)
            assert.equals(2, bps[1].line)
        end)

        it("should find nearest match when one duplicate is clearly closer", function()
            breakpoints.set_persistence(persist_config)

            -- Open file and set breakpoint on line 5 (println!("y = {}", y);)
            vim.cmd("edit " .. vim.fn.fnameescape(main_rs_path))
            vim.api.nvim_win_set_cursor(0, { 5, 0 })
            breakpoints.create()

            -- Save
            breakpoints.save_to_disk()
            vim.cmd("bwipeout!")

            -- Create file with duplicate lines OUTSIDE vim
            -- Original breakpoint was at line 5, now we have duplicates at 2, 6, and 10
            -- Line 6 (distance=1) should win over line 2 (distance=3) and line 10 (distance=5)
            local modified_content = {
                "fn main() {",
                '    println!("y = {}", y);', -- Line 2 - duplicate (distance 3 from line 5)
                "    let a = 1;",
                "    let b = 2;",
                "    let c = 3;",
                '    println!("y = {}", y);', -- Line 6 - duplicate (distance 1 from line 5) - NEAREST
                "    let d = 4;",
                "    let e = 5;",
                "    let f = 6;",
                '    println!("y = {}", y);', -- Line 10 - duplicate (distance 5 from line 5)
                "}",
            }
            vim.fn.writefile(modified_content, main_rs_path)

            -- Reload module
            package.loaded["breakpoints"] = nil
            breakpoints = require("breakpoints")
            breakpoints.set_persistence(persist_config)

            -- Load from disk
            breakpoints.load_from_disk()

            -- Should find the match nearest to original line 5, which is line 6
            local bps = breakpoints.get_all()
            assert.equals(1, #bps)
            assert.equals(6, bps[1].line)
        end)

        it("should fail when line content completely removed", function()
            breakpoints.set_persistence(persist_config)

            -- Open file and set breakpoint on "let x = 42;"
            vim.cmd("edit " .. vim.fn.fnameescape(main_rs_path))
            vim.api.nvim_win_set_cursor(0, { 3, 0 })
            breakpoints.create()

            -- Save
            breakpoints.save_to_disk()
            vim.cmd("bwipeout!")

            -- Remove the line entirely OUTSIDE vim
            local modified_content = {
                "fn main() {",
                "    println!(\"Line 2\");",
                "    // let x = 42; is gone now",
                "    let y = 100;",
                "    println!(\"y = {}\", y);",
                "}",
            }
            vim.fn.writefile(modified_content, main_rs_path)

            -- Reload module
            package.loaded["breakpoints"] = nil
            breakpoints = require("breakpoints")
            breakpoints.set_persistence(persist_config)

            -- Load from disk - should not throw
            assert.has_no.errors(function()
                breakpoints.load_from_disk()
            end)

            -- Breakpoint should not be restored (no matching hash)
            local bps = breakpoints.get_all()
            assert.equals(0, #bps)
        end)
    end)

    describe("mixed scenarios", function()
        it("should handle mix of valid and invalid breakpoints", function()
            local persist_config = { enabled = true, line_locator = "exact" }
            breakpoints.set_persistence(persist_config)

            -- Set breakpoints on lines 3, 5, and 7
            vim.cmd("edit " .. vim.fn.fnameescape(main_rs_path))
            vim.api.nvim_win_set_cursor(0, { 3, 0 })
            breakpoints.create()
            vim.api.nvim_win_set_cursor(0, { 5, 0 })
            breakpoints.create()
            vim.api.nvim_win_set_cursor(0, { 7, 0 })
            breakpoints.create()

            -- Save
            breakpoints.save_to_disk()
            vim.cmd("bwipeout!")

            -- Truncate to 5 lines (line 7 becomes invalid)
            local truncated = {
                "fn main() {",
                "    println!(\"Line 2\");",
                "    let x = 42;",
                "    let y = x + 1;",
                "}",
            }
            vim.fn.writefile(truncated, main_rs_path)

            -- Reload
            package.loaded["breakpoints"] = nil
            breakpoints = require("breakpoints")
            breakpoints.set_persistence(persist_config)

            -- Load
            assert.has_no.errors(function()
                breakpoints.load_from_disk()
            end)

            -- Lines 3 and 5 should be restored, line 7 should be skipped
            local bps = breakpoints.get_all()
            assert.equals(2, #bps)

            local lines = {}
            for _, bp in ipairs(bps) do
                table.insert(lines, bp.line)
            end
            table.sort(lines)
            assert.same({ 3, 5 }, lines)
        end)
    end)
end)
