local termdebug = require("termdebug")
local options = require("options")

local cargo = {}

-- build tests and record the test artifacts (test binaries)
cargo.build_tests = function()
    -- build test binaries and capture their locations
    local cargo_cmd = "cargo --quiet test --workspace --no-run --message-format=json"
    local cargo_output = vim.fn.system(cargo_cmd)

    if vim.v.shell_error ~= 0 then
        vim.notify("cargo command failed.", vim.log.levels.ERROR)
        return
    end

    local test_artifacts = {}
    for _, line in ipairs(vim.split(cargo_output, "\n")) do
        if line ~= "" then
            local ok, artifact = pcall(vim.json.decode, line)
            if
                ok
                and type(artifact) == "table"
                and artifact.reason == "compiler-artifact"
                and artifact.profile
                and artifact.profile.test == true
                and artifact.executable ~= nil
            then
                table.insert(test_artifacts, { name = artifact.target.name, path = artifact.executable })
            end
        end
    end

    return test_artifacts
end

-- Finds the crate name for the currently active file by using cargo.
cargo.current_crate_name = function(file_dir, metadata)
    if file_dir == "" then
        return nil
    end

    local original_dir = vim.fn.getcwd()
    local locate_output

    pcall(function()
        -- cd into the directory of the current file
        vim.fn.chdir(file_dir)
        -- locate the crate's Cargo.toml
        locate_output = vim.fn.system("cargo locate-project --message-format=json")
    end)
    -- restore original directory
    vim.fn.chdir(original_dir)

    if not locate_output or vim.v.shell_error ~= 0 then
        return nil
    end

    local current_manifest_path = vim.json.decode(locate_output).root

    -- find the package whose manifest_path matches the one we found.
    for _, package in ipairs(metadata.packages) do
        if package.manifest_path == current_manifest_path then
            return package.name
        end
    end

    return nil
end

cargo.metadata = function()
    local metadata_json = vim.fn.system("cargo metadata --no-deps --format-version=1")
    if vim.v.shell_error ~= 0 then
        vim.notify("cargo metadata command failed", vim.log.levels.ERROR)
        return
    end
    return vim.json.decode(metadata_json)
end

cargo.debug_bin = function()
    local metadata = cargo.metadata()
    local target_dir = metadata.target_directory

    local all_binaries = {}
    for _, package in ipairs(metadata.packages) do
        for _, target in ipairs(package.targets) do
            if vim.deep_equal(target.kind, { "bin" }) then
                table.insert(all_binaries, { name = target.name, package_name = package.name })
            end
        end
    end

    if #all_binaries == 0 then
        vim.notify("No binaries found in this project.", vim.log.levels.WARN)
        return
    end

    local file_dir = vim.fn.expand("%:p:h")
    local current_crate_name = cargo.current_crate_name(file_dir, metadata)

    -- in the binary selection list, put binaries associated with the current file first
    local sorted_binaries = {}
    if current_crate_name then
        local other_binaries = {}
        for _, bin_info in ipairs(all_binaries) do
            if bin_info.package_name == current_crate_name then
                table.insert(sorted_binaries, bin_info)
            else
                table.insert(other_binaries, bin_info)
            end
        end
        vim.list_extend(sorted_binaries, other_binaries)
    else
        sorted_binaries = all_binaries
    end

    local function rust_build_and_debug(bin_crate_name)
        local bin_path = target_dir .. "/debug/" .. bin_crate_name
        vim.notify("Running cargo build", vim.log.levels.INFO)
        local build_output = vim.fn.system("cargo build --bin " .. bin_crate_name)
        if vim.v.shell_error ~= 0 then
            vim.notify("cargo build failed", vim.log.levels.ERROR)
            print(build_output)
            return
        end
        local original_win_id = vim.api.nvim_get_current_win()
        vim.notify("Debugging: " .. bin_path, vim.log.levels.INFO)
        termdebug.start(bin_path, original_win_id)
    end

    if #sorted_binaries == 1 then
        -- build and debug the one and only binary
        rust_build_and_debug(sorted_binaries[1].name)
    else
        -- choose which binary to build and debug
        local choices = {}
        for _, bin_info in ipairs(sorted_binaries) do
            table.insert(choices, bin_info.name)
        end
        vim.ui.select(choices, { prompt = "Select a binary to debug:" }, function(choice, idx)
            if choice then
                rust_build_and_debug(sorted_binaries[idx].name)
            end
        end)
    end
end

cargo.debug_tests = function()
    vim.notify("Compiling workspace tests...", vim.log.levels.INFO)

    local test_artifacts = cargo.build_tests()
    local metadata = cargo.metadata()

    if #test_artifacts == 0 then
        vim.notify("Failed to find any test executables.", vim.log.levels.ERROR)
        return
    end

    if #test_artifacts > 1 then
        -- Use the new reusable function to get the current crate's name.
        local file_dir = vim.fn.expand("%:p:h")
        local current_crate_name = cargo.current_crate_name(file_dir, metadata)
        if current_crate_name then
            local current_artifact_idx
            for i, artifact in ipairs(test_artifacts) do
                if artifact.name == current_crate_name then
                    current_artifact_idx = i
                    break
                end
            end
            if current_artifact_idx then
                local prioritized_artifact = table.remove(test_artifacts, current_artifact_idx)
                table.insert(test_artifacts, 1, prioritized_artifact)
            end
        end
    end

    local original_win_id = vim.api.nvim_get_current_win()
    if #test_artifacts == 1 then
        local bin_path = test_artifacts[1].path
        vim.notify("Debugging test: " .. bin_path, vim.log.levels.INFO)
        termdebug.start(bin_path, original_win_id)
    else
        local choices = {}
        for _, artifact in ipairs(test_artifacts) do
            table.insert(choices, "Test module: " .. artifact.name)
        end

        vim.ui.select(choices, { prompt = "Select a test binary to debug:" }, function(choice, idx)
            if not choice then
                return
            end
            local selected_path = test_artifacts[idx].path
            vim.notify("Debugging test: " .. selected_path, vim.log.levels.INFO)
            termdebug.start(selected_path, original_win_id)
        end)
    end
end

return cargo
