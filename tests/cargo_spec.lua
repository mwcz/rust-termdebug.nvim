-- Basic smoke tests for rust-termdebug.nvim
-- Run with: nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

describe("cargo module", function()
    local cargo

    before_each(function()
        -- Navigate to test fixture
        vim.cmd("cd tests/fixtures/test-project")
        -- Reload cargo module
        package.loaded["cargo"] = nil
        cargo = require("cargo")
    end)

    after_each(function()
        vim.cmd("cd ../../..")
    end)

    describe("cargo.metadata", function()
        it("should return workspace metadata", function()
            local metadata = cargo.metadata()
            assert.is_not_nil(metadata)
            assert.is_not_nil(metadata.workspace_root)
            assert.is_not_nil(metadata.target_directory)
            assert.is_not_nil(metadata.packages)
            assert.is_true(#metadata.packages > 0)
        end)

        it("should find workspace members", function()
            local metadata = cargo.metadata()
            local package_names = {}
            for _, pkg in ipairs(metadata.packages) do
                table.insert(package_names, pkg.name)
            end

            assert.is_true(vim.tbl_contains(package_names, "test-project"))
            assert.is_true(vim.tbl_contains(package_names, "mylib"))
            assert.is_true(vim.tbl_contains(package_names, "another-bin"))
        end)
    end)

    describe("cargo.current_crate_name", function()
        it("should identify crate from file path", function()
            local metadata = cargo.metadata()
            local workspace_root = metadata.workspace_root

            -- Test main binary crate
            local crate_name = cargo.current_crate_name(workspace_root .. "/src", metadata)
            assert.equals("test-project", crate_name)

            -- Test library crate
            local lib_name = cargo.current_crate_name(workspace_root .. "/mylib/src", metadata)
            assert.equals("mylib", lib_name)

            -- Test another binary crate
            local bin_name = cargo.current_crate_name(workspace_root .. "/another-bin/src", metadata)
            assert.equals("another-bin", bin_name)
        end)

        it("should return nil for invalid path", function()
            local metadata = cargo.metadata()
            local crate_name = cargo.current_crate_name("/nonexistent/path", metadata)
            assert.is_nil(crate_name)
        end)
    end)

    describe("cargo.build_tests", function()
        it("should compile and collect test artifacts", function()
            local artifacts
            local completed = false

            cargo.build_tests(function(test_artifacts)
                artifacts = test_artifacts
                completed = true
            end)

            -- Wait for async completion (with timeout)
            local timeout = 30000 -- 30 seconds
            local start = vim.loop.now()
            while not completed and (vim.loop.now() - start) < timeout do
                vim.wait(100)
            end

            assert.is_true(completed, "build_tests did not complete in time")
            assert.is_not_nil(artifacts)
            assert.is_true(#artifacts > 0, "no test artifacts found")

            -- Check that artifacts have expected structure
            for _, artifact in ipairs(artifacts) do
                assert.is_not_nil(artifact.name)
                assert.is_not_nil(artifact.path)
                assert.is_not_nil(artifact.kind)
            end
        end)
    end)

    describe("cargo.build_benches", function()
        it("should compile and collect benchmark artifacts", function()
            local artifacts
            local completed = false

            cargo.build_benches(function(bench_artifacts)
                artifacts = bench_artifacts
                completed = true
            end)

            -- Wait for async completion (with timeout)
            local timeout = 30000 -- 30 seconds
            local start = vim.loop.now()
            while not completed and (vim.loop.now() - start) < timeout do
                vim.wait(100)
            end

            assert.is_true(completed, "build_benches did not complete in time")
            assert.is_not_nil(artifacts)
            assert.is_true(#artifacts > 0, "no benchmark artifacts found")

            -- Check that artifacts have expected structure
            for _, artifact in ipairs(artifacts) do
                assert.is_not_nil(artifact.name)
                assert.is_not_nil(artifact.path)
                assert.is_not_nil(artifact.kind)
                assert.equals("benchmark1", artifact.name)
            end
        end)
    end)

    describe("cargo.clear_pins", function()
        it("should clear all pinned selections", function()
            -- This is a simple smoke test - just make sure it doesn't error
            assert.has_no.errors(function()
                cargo.clear_pins()
            end)
        end)
    end)
end)
