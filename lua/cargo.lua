local termdebug = require("termdebug")
local options = require("options")

local cargo = {}

local run_build = function(build_cmd, on_success)
    vim.cmd("botright 15split | terminal " .. build_cmd)

    local job_id = vim.b.terminal_job_id
    local win_id = vim.api.nvim_get_current_win()
    local bufnr = vim.api.nvim_get_current_buf()

    vim.bo[bufnr].buflisted = false

    -- set a buffer-local keymap to close the window with `q` or `<c-d>`, for both normal and terminal modes.
    -- TODO: make these keymaps configurable
    for _, lhs in ipairs({ "q", "<c-d>" }) do
        -- normal mode
        vim.keymap.set("n", lhs, "<Cmd>close!<CR>", {
            noremap = true,
            silent = true,
            buffer = bufnr,
            desc = "Close build terminal",
        })
        -- terminal mode
        vim.keymap.set("t", lhs, "<C-\\><C-n><Cmd>close!<CR>", {
            silent = true,
            buffer = bufnr,
            desc = "Close build terminal",
        })
    end

    -- Listen for the TermClose event to get the exit code
    vim.api.nvim_create_autocmd("TermClose", {
        buffer = bufnr,
        once = true,
        callback = function()
            local exit_code = vim.v.event.status

            if exit_code ~= 0 then
                vim.notify("Error: cargo build failed (exit code: " .. exit_code .. ")", vim.log.levels.ERROR)
                return
            end

            if vim.api.nvim_win_is_valid(win_id) then
                vim.api.nvim_win_close(win_id, true)
            end

            if on_success then
                on_success()
            end
        end,
    })
end

-- build tests and record the test artifacts (test binaries)
cargo.build_tests = function(on_complete)
    local user_cmd = "cargo test --workspace --no-run --tests"

    run_build(user_cmd, function()
        vim.notify("Build successful, collecting test artifacts...", vim.log.levels.INFO)
        local json_cmd = "cargo test --workspace --no-run --tests --message-format=json"
        local cargo_output = vim.fn.system(json_cmd)

        if vim.v.shell_error ~= 0 then
            vim.notify("Error: Failed to collect test artifacts after successful build.", vim.log.levels.ERROR)
            on_complete(nil)
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
                    table.insert(test_artifacts, {
                        name = artifact.target.name,
                        path = artifact.executable,
                        kind = artifact.target.kind,
                    })
                end
            end
        end
        on_complete(test_artifacts)
    end)
end

-- build benchmarks and record the benchmark artifacts (benchmark binaries)
cargo.build_benches = function(on_complete)
    local user_cmd = "cargo bench --workspace --no-run --benches"

    run_build(user_cmd, function()
        vim.notify("Build successful, collecting benchmark artifacts...", vim.log.levels.INFO)
        local json_cmd = "cargo bench --workspace --no-run --benches --message-format=json"
        local cargo_output = vim.fn.system(json_cmd)

        if vim.v.shell_error ~= 0 then
            vim.notify("Error: Failed to collect benchmark artifacts after successful build.", vim.log.levels.ERROR)
            on_complete(nil)
            return
        end

        local bench_artifacts = {}
        for _, line in ipairs(vim.split(cargo_output, "\n")) do
            if line ~= "" then
                local ok, artifact = pcall(vim.json.decode, line)
                if
                    ok
                    and type(artifact) == "table"
                    and artifact.reason == "compiler-artifact"
                    and artifact.executable ~= nil
                then
                    -- Check if this is a bench target
                    local is_bench = false
                    if artifact.target and artifact.target.kind then
                        for _, kind in ipairs(artifact.target.kind) do
                            if kind == "bench" then
                                is_bench = true
                                break
                            end
                        end
                    end

                    if is_bench then
                        table.insert(bench_artifacts, {
                            name = artifact.target.name,
                            path = artifact.executable,
                            kind = artifact.target.kind,
                        })
                    end
                end
            end
        end
        on_complete(bench_artifacts)
    end)
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

-- Session-local variables to store pinned selections
local pinned_binary = nil
local pinned_test = nil
local pinned_example = nil
local pinned_bench = nil

cargo.debug_bin = function()
    local metadata = cargo.metadata()
    if not metadata then
        return
    end
    local target_dir = metadata.target_directory

    local function rust_build_and_debug(bin_crate_name)
        local bin_path = target_dir .. "/debug/" .. bin_crate_name
        local build_cmd = "cargo build --bin " .. bin_crate_name

        vim.notify("Building binary: " .. bin_crate_name, vim.log.levels.INFO)

        local original_win_id = vim.api.nvim_get_current_win()

        run_build(build_cmd, function()
            vim.notify("Debugging: " .. bin_path, vim.log.levels.INFO)
            termdebug.start(bin_path, original_win_id)
        end)
    end

    -- If there's a pinned binary, use it automatically
    if pinned_binary then
        rust_build_and_debug(pinned_binary)
        return
    end

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

    -- discover the root crate
    local root_manifest_path = metadata.workspace_root .. "/Cargo.toml"
    local root_crate_name
    for _, package in ipairs(metadata.packages) do
        if package.manifest_path == root_manifest_path then
            root_crate_name = package.name
            break
        end
    end

    -- put binaries in this order:
    --   1. binary of crate currently being edited
    --   2. binary of the root crate
    --   3. binaries of other crates in the workspace
    local current_binaries = {}
    local root_binaries = {}
    local other_binaries = {}

    for _, bin_info in ipairs(all_binaries) do
        if bin_info.package_name == current_crate_name then
            table.insert(current_binaries, bin_info)
        elseif bin_info.package_name == root_crate_name then
            table.insert(root_binaries, bin_info)
        else
            table.insert(other_binaries, bin_info)
        end
    end

    local priority_bin_list = {}
    vim.list_extend(priority_bin_list, current_binaries)
    vim.list_extend(priority_bin_list, root_binaries)
    vim.list_extend(priority_bin_list, other_binaries)

    if #priority_bin_list == 1 then
        -- build and debug the one and only binary
        rust_build_and_debug(priority_bin_list[1].name)
    else
        -- choose which binary to build and debug
        local choices = {}
        local pin_suffix = options.current.pin_suffix

        -- Find the longest binary name for alignment
        local max_len = 0
        for _, bin_info in ipairs(priority_bin_list) do
            if #bin_info.name > max_len then
                max_len = #bin_info.name
            end
        end

        for _, bin_info in ipairs(priority_bin_list) do
            local padding = string.rep(" ", max_len - #bin_info.name)
            table.insert(choices, bin_info.name .. padding .. pin_suffix)
            table.insert(choices, bin_info.name)
        end

        vim.ui.select(choices, { prompt = "Select a binary to debug:" }, function(choice)
            if choice then
                local bin_to_debug
                -- Check if the user chose a "pin" option (strip padding and suffix)
                local trimmed_choice = choice:gsub("%s+$", "")
                if choice:sub(-#pin_suffix) == pin_suffix then
                    -- Extract the binary name and save it to the session variable
                    bin_to_debug = choice:match("^(%S+)")
                    pinned_binary = bin_to_debug
                    vim.notify("Pinned " .. bin_to_debug .. " as default for this session.", vim.log.levels.INFO)
                else
                    bin_to_debug = choice
                end
                rust_build_and_debug(bin_to_debug)
            end
        end)
    end
end

cargo.debug_tests = function()
    vim.notify("Compiling workspace tests...", vim.log.levels.INFO)
    local metadata_json = vim.fn.system("cargo metadata --no-deps --format-version=1")
    local metadata = vim.json.decode(metadata_json)

    cargo.build_tests(function(test_artifacts)
        if test_artifacts == nil then
            return
        end

        if #test_artifacts == 0 then
            vim.notify("Failed to find any test executables.", vim.log.levels.ERROR)
            return
        end

        if #test_artifacts > 1 then
            local file_path = vim.fn.expand("%:p")
            local file_dir = vim.fn.expand("%:p:h")
            local current_artifact_idx

            -- check if this is an integration test (/tests/)
            if string.find(file_path, "/tests/", 1, true) then
                local test_name = vim.fn.fnamemodify(file_path, ":t:r") -- Get filename without extension
                for i, artifact in ipairs(test_artifacts) do
                    -- if kind contains "test"
                    local is_integration_test = false
                    for _, kind in ipairs(artifact.kind) do
                        if kind == "test" then
                            is_integration_test = true
                        end
                    end

                    if artifact.name == test_name and is_integration_test then
                        current_artifact_idx = i
                        break
                    end
                end
            else
                local current_crate_name = cargo.current_crate_name(file_dir, metadata)
                if current_crate_name then
                    local target_kind_heuristic = "lib"
                    if
                        string.find(file_path, "/src/main.rs", 1, true) or string.find(file_path, "/src/bin/", 1, true)
                    then
                        target_kind_heuristic = "bin"
                    end
                    for i, artifact in ipairs(test_artifacts) do
                        -- if kind contains the target kind
                        local is_right_kind = false
                        for _, kind in ipairs(artifact.kind) do
                            if kind == target_kind_heuristic then
                                is_right_kind = true
                            end
                        end

                        if artifact.name == current_crate_name and is_right_kind then
                            current_artifact_idx = i
                            break
                        end
                    end
                end
            end

            if current_artifact_idx then
                local prioritized_artifact = table.remove(test_artifacts, current_artifact_idx)
                table.insert(test_artifacts, 1, prioritized_artifact)
            end
        end

        -- If there's a pinned test, find and use it automatically
        if pinned_test then
            local original_win_id = vim.api.nvim_get_current_win()
            for _, artifact in ipairs(test_artifacts) do
                if artifact.name == pinned_test then
                    vim.notify("Debugging pinned test: " .. artifact.name, vim.log.levels.INFO)
                    termdebug.start(artifact.path, original_win_id)
                    return
                end
            end
            -- If pinned test not found, notify and continue to selection
            vim.notify("Pinned test '" .. pinned_test .. "' not found, showing selection...", vim.log.levels.WARN)
        end

        -- The rest of the logic for selecting and launching the debugger remains the same.
        local original_win_id = vim.api.nvim_get_current_win()
        if #test_artifacts == 1 then
            local bin_path = test_artifacts[1].path
            vim.notify("Debugging test: " .. bin_path, vim.log.levels.INFO)
            termdebug.start(bin_path, original_win_id)
        else
            local choices = {}
            local pin_suffix = options.current.pin_suffix

            -- Find the longest display name for alignment
            local max_len = 0
            local display_names = {}
            for _, artifact in ipairs(test_artifacts) do
                local kinds = table.concat(artifact.kind, ", ")
                local display_name = "Test module: " .. artifact.name .. " (" .. kinds .. ")"
                table.insert(display_names, display_name)
                if #display_name > max_len then
                    max_len = #display_name
                end
            end

            for i, display_name in ipairs(display_names) do
                local padding = string.rep(" ", max_len - #display_name)
                table.insert(choices, display_name .. padding .. pin_suffix)
                table.insert(choices, display_name)
            end

            vim.ui.select(choices, { prompt = "Select a test binary to debug:" }, function(choice, idx)
                if not choice then
                    return
                end

                -- Calculate the actual artifact index (accounting for pin entries)
                local artifact_idx = math.ceil(idx / 2)
                local selected_artifact = test_artifacts[artifact_idx]

                -- Check if the user chose a "pin" option
                if choice:sub(-#pin_suffix) == pin_suffix then
                    pinned_test = selected_artifact.name
                    vim.notify("Pinned test: " .. selected_artifact.name, vim.log.levels.INFO)
                end

                vim.notify("Debugging test: " .. selected_artifact.path, vim.log.levels.INFO)
                termdebug.start(selected_artifact.path, original_win_id)
            end)
        end
    end)
end

cargo.debug_example = function()
    local metadata = cargo.metadata()
    if not metadata then
        return
    end
    local target_dir = metadata.target_directory

    local function build_and_debug_example(example_name)
        local example_path = target_dir .. "/debug/examples/" .. example_name
        local build_cmd = "cargo build --example " .. example_name

        vim.notify("Building example: " .. example_name, vim.log.levels.INFO)

        local original_win_id = vim.api.nvim_get_current_win()

        run_build(build_cmd, function()
            vim.notify("Debugging example: " .. example_path, vim.log.levels.INFO)
            termdebug.start(example_path, original_win_id)
        end)
    end

    -- If there's a pinned example, use it automatically
    if pinned_example then
        build_and_debug_example(pinned_example)
        return
    end

    vim.notify("Finding examples...", vim.log.levels.INFO)

    local examples = {}
    for _, package in ipairs(metadata.packages) do
        for _, target in ipairs(package.targets) do
            if vim.deep_equal(target.kind, { "example" }) then
                table.insert(examples, { name = target.name })
            end
        end
    end

    if #examples == 0 then
        vim.notify("No examples found in this project.", vim.log.levels.WARN)
        return
    end

    -- move the currently edited file to the top of the list
    local file_path = vim.fn.expand("%:p")
    if string.find(file_path, "/examples/", 1, true) then
        local example_name = vim.fn.fnamemodify(file_path, ":t:r")
        local current_example_idx
        for i, example in ipairs(examples) do
            if example.name == example_name then
                current_example_idx = i
                break
            end
        end
        if current_example_idx then
            local prioritized_example = table.remove(examples, current_example_idx)
            table.insert(examples, 1, prioritized_example)
        end
    end

    if #examples == 1 then
        build_and_debug_example(examples[1].name)
    else
        local choices = {}
        local pin_suffix = options.current.pin_suffix

        -- Find the longest display name for alignment
        local max_len = 0
        local display_names = {}
        for _, example in ipairs(examples) do
            local display_name = "Example: " .. example.name
            table.insert(display_names, display_name)
            if #display_name > max_len then
                max_len = #display_name
            end
        end

        for i, display_name in ipairs(display_names) do
            local padding = string.rep(" ", max_len - #display_name)
            table.insert(choices, display_name .. padding .. pin_suffix)
            table.insert(choices, display_name)
        end

        vim.ui.select(choices, { prompt = "Select an example to debug:" }, function(choice, idx)
            if not choice then
                vim.notify("Debugger launch cancelled.", vim.log.levels.INFO)
                return
            end

            -- Calculate the actual example index (accounting for pin entries)
            local example_idx = math.ceil(idx / 2)
            local selected_example = examples[example_idx].name

            -- Check if the user chose a "pin" option
            if choice:sub(-#pin_suffix) == pin_suffix then
                pinned_example = selected_example
                vim.notify("Pinned example: " .. selected_example, vim.log.levels.INFO)
            end

            build_and_debug_example(selected_example)
        end)
    end
end

cargo.debug_benches = function()
    vim.notify("Compiling workspace benchmarks...", vim.log.levels.INFO)
    local metadata_json = vim.fn.system("cargo metadata --no-deps --format-version=1")
    local metadata = vim.json.decode(metadata_json)

    cargo.build_benches(function(bench_artifacts)
        if bench_artifacts == nil then
            return
        end

        if #bench_artifacts == 0 then
            vim.notify("Failed to find any benchmark executables.", vim.log.levels.ERROR)
            return
        end

        if #bench_artifacts > 1 then
            local file_path = vim.fn.expand("%:p")
            local file_dir = vim.fn.expand("%:p:h")
            local current_artifact_idx

            -- check if this is a benchmark file (/benches/)
            if string.find(file_path, "/benches/", 1, true) then
                local bench_name = vim.fn.fnamemodify(file_path, ":t:r") -- Get filename without extension
                for i, artifact in ipairs(bench_artifacts) do
                    if artifact.name == bench_name then
                        current_artifact_idx = i
                        break
                    end
                end
            else
                local current_crate_name = cargo.current_crate_name(file_dir, metadata)
                if current_crate_name then
                    for i, artifact in ipairs(bench_artifacts) do
                        if artifact.name == current_crate_name then
                            current_artifact_idx = i
                            break
                        end
                    end
                end
            end

            if current_artifact_idx then
                local prioritized_artifact = table.remove(bench_artifacts, current_artifact_idx)
                table.insert(bench_artifacts, 1, prioritized_artifact)
            end
        end

        -- If there's a pinned benchmark, find and use it automatically
        if pinned_bench then
            local original_win_id = vim.api.nvim_get_current_win()
            for _, artifact in ipairs(bench_artifacts) do
                if artifact.name == pinned_bench then
                    vim.notify("Debugging pinned benchmark: " .. artifact.name, vim.log.levels.INFO)
                    termdebug.start(artifact.path, original_win_id)
                    return
                end
            end
            -- If pinned benchmark not found, notify and continue to selection
            vim.notify("Pinned benchmark '" .. pinned_bench .. "' not found, showing selection...", vim.log.levels.WARN)
        end

        local original_win_id = vim.api.nvim_get_current_win()
        if #bench_artifacts == 1 then
            local bin_path = bench_artifacts[1].path
            vim.notify("Debugging benchmark: " .. bin_path, vim.log.levels.INFO)
            termdebug.start(bin_path, original_win_id)
        else
            local choices = {}
            local pin_suffix = options.current.pin_suffix

            -- Find the longest display name for alignment
            local max_len = 0
            local display_names = {}
            for _, artifact in ipairs(bench_artifacts) do
                local kinds = table.concat(artifact.kind, ", ")
                local display_name = "Benchmark: " .. artifact.name .. " (" .. kinds .. ")"
                table.insert(display_names, display_name)
                if #display_name > max_len then
                    max_len = #display_name
                end
            end

            for i, display_name in ipairs(display_names) do
                local padding = string.rep(" ", max_len - #display_name)
                table.insert(choices, display_name .. padding .. pin_suffix)
                table.insert(choices, display_name)
            end

            vim.ui.select(choices, { prompt = "Select a benchmark to debug:" }, function(choice, idx)
                if not choice then
                    return
                end

                -- Calculate the actual artifact index (accounting for pin entries)
                local artifact_idx = math.ceil(idx / 2)
                local selected_artifact = bench_artifacts[artifact_idx]

                -- Check if the user chose a "pin" option
                if choice:sub(-#pin_suffix) == pin_suffix then
                    pinned_bench = selected_artifact.name
                    vim.notify("Pinned benchmark: " .. selected_artifact.name, vim.log.levels.INFO)
                end

                vim.notify("Debugging benchmark: " .. selected_artifact.path, vim.log.levels.INFO)
                termdebug.start(selected_artifact.path, original_win_id)
            end)
        end
    end)
end

cargo.clear_pins = function()
    pinned_binary = nil
    pinned_test = nil
    pinned_example = nil
    pinned_bench = nil
    vim.notify("Cleared all pinned selections", vim.log.levels.INFO)
end

return cargo
