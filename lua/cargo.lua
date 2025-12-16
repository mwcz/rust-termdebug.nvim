local termdebug = require("termdebug")
local breakpoints = require("breakpoints")
local options = require("options")

local cargo = {}

-- Returns the target directory name for a given profile
-- "dev" -> "debug", "release" -> "release", custom -> custom
local function profile_to_target_dir(profile)
    if profile == "dev" then
        return "debug"
    end
    return profile
end

-- Returns cargo build flags for a given profile
-- "dev" -> "", "release" -> "--release", custom -> "--profile <name>"
local function profile_to_build_flag(profile)
    if profile == "dev" then
        return ""
    elseif profile == "release" then
        return "--release"
    else
        return "--profile " .. profile
    end
end

-- Parse available profiles from workspace Cargo.toml
-- Returns {"dev", "release", ...custom profiles}
local function get_available_profiles(workspace_root)
    local profiles = { "dev", "release" }
    local cargo_toml_path = workspace_root .. "/Cargo.toml"

    local cargo_toml = vim.fn.readfile(cargo_toml_path)
    if not cargo_toml then
        return profiles
    end

    for _, line in ipairs(cargo_toml) do
        local custom_profile = line:match("^%[profile%.([^%]]+)%]")
        if custom_profile and custom_profile ~= "dev" and custom_profile ~= "release" then
            table.insert(profiles, custom_profile)
        end
    end

    return profiles
end

-- Debug session types
local DebugType = {
    BINARY = "binary",
    TEST = "test",
    EXAMPLE = "example",
    BENCH = "bench",
}

local run_build = function(build_cmd, on_success)
    local original_win_id = vim.api.nvim_get_current_win()

    vim.cmd("botright 15split | terminal " .. build_cmd)

    local job_id = vim.b.terminal_job_id
    local win_id = vim.api.nvim_get_current_win()
    local bufnr = vim.api.nvim_get_current_buf()

    vim.bo[bufnr].buflisted = false

    -- move cursor to bottom of terminal so that new output will scroll into view as it arrives
    vim.cmd("normal! G")
    vim.api.nvim_set_current_win(original_win_id)

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
-- pinned_binary stores { name = "binary_name", profile = "dev" }
local pinned_binary = nil
local pinned_test = nil
local pinned_example = nil
local pinned_bench = nil

cargo.debug_bin = function()
    -- If there's an active binary session, rebuild and reload instead
    local session = termdebug.get_active_session()
    if session and session.type == DebugType.BINARY then
        cargo.rebuild_and_reload()
        return
    end

    local metadata = cargo.metadata()
    if not metadata then
        return
    end
    local target_dir = metadata.target_directory
    local profiles = get_available_profiles(metadata.workspace_root)

    local function rust_build_and_debug(bin_crate_name, profile)
        local target_subdir = profile_to_target_dir(profile)
        local bin_path = target_dir .. "/" .. target_subdir .. "/" .. bin_crate_name
        local profile_flag = profile_to_build_flag(profile)
        local build_cmd = "cargo build --bin " .. bin_crate_name
        if profile_flag ~= "" then
            build_cmd = build_cmd .. " " .. profile_flag
        end

        vim.notify("Building binary: " .. bin_crate_name .. " (" .. profile .. ")", vim.log.levels.INFO)

        local original_win_id = vim.api.nvim_get_current_win()

        run_build(build_cmd, function()
            vim.notify("Debugging: " .. bin_path, vim.log.levels.INFO)
            termdebug.start(bin_path, {
                original_win_id = original_win_id,
                type = DebugType.BINARY,
                name = bin_crate_name,
                profile = profile,
                build_cmd = build_cmd,
            })
        end)
    end

    -- If there's a pinned binary+profile, use it automatically
    if pinned_binary then
        rust_build_and_debug(pinned_binary.name, pinned_binary.profile)
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

    -- Build choices: binary + profile combinations
    -- Each combination has a pin and non-pin variant
    local choices = {}
    local choice_data = {} -- parallel array to store {name, profile, pin} for each choice
    local pin_suffix = options.current.pin_suffix

    -- Find the longest binary name and profile for alignment
    local max_name_len = 0
    local max_profile_len = 0
    for _, bin_info in ipairs(priority_bin_list) do
        if #bin_info.name > max_name_len then
            max_name_len = #bin_info.name
        end
    end
    for _, profile in ipairs(profiles) do
        if #profile > max_profile_len then
            max_profile_len = #profile
        end
    end

    -- Build the choice list: for each binary, show all profiles
    -- Format: "binary_name<tab>(profile)<padding>[pin]"
    for _, bin_info in ipairs(priority_bin_list) do
        for _, profile in ipairs(profiles) do
            local name_padding = string.rep(" ", max_name_len - #bin_info.name)
            local profile_padding = string.rep(" ", max_profile_len - #profile)
            local display = bin_info.name .. name_padding .. "\t(" .. profile .. ")" .. profile_padding
            -- Pin option first
            table.insert(choices, display .. pin_suffix)
            table.insert(choice_data, { name = bin_info.name, profile = profile, pin = true })
            -- Non-pin option
            table.insert(choices, display)
            table.insert(choice_data, { name = bin_info.name, profile = profile, pin = false })
        end
    end

    vim.ui.select(choices, { prompt = "Select a binary to debug:" }, function(_, idx)
        if not idx then
            return
        end

        local selected = choice_data[idx]
        if selected.pin then
            pinned_binary = { name = selected.name, profile = selected.profile }
            vim.notify(
                "Pinned " .. selected.name .. " (" .. selected.profile .. ") as default for this session.",
                vim.log.levels.INFO
            )
        end
        rust_build_and_debug(selected.name, selected.profile)
    end)
end

cargo.debug_tests = function()
    -- If there's an active test session, rebuild and reload instead
    local session = termdebug.get_active_session()
    if session and session.type == DebugType.TEST then
        cargo.rebuild_and_reload()
        return
    end

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
                    termdebug.start(artifact.path, {
                        original_win_id = original_win_id,
                        type = DebugType.TEST,
                        name = artifact.name,
                    })
                    return
                end
            end
            -- If pinned test not found, notify and continue to selection
            vim.notify("Pinned test '" .. pinned_test .. "' not found, showing selection...", vim.log.levels.WARN)
        end

        -- The rest of the logic for selecting and launching the debugger remains the same.
        local original_win_id = vim.api.nvim_get_current_win()
        if #test_artifacts == 1 then
            local artifact = test_artifacts[1]
            local bin_path = artifact.path
            vim.notify("Debugging test: " .. bin_path, vim.log.levels.INFO)
            termdebug.start(bin_path, {
                original_win_id = original_win_id,
                type = DebugType.TEST,
                name = artifact.name,
            })
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
                termdebug.start(selected_artifact.path, {
                    original_win_id = original_win_id,
                    type = DebugType.TEST,
                    name = selected_artifact.name,
                })
            end)
        end
    end)
end

cargo.debug_example = function()
    -- If there's an active example session, rebuild and reload instead
    local session = termdebug.get_active_session()
    if session and session.type == DebugType.EXAMPLE then
        cargo.rebuild_and_reload()
        return
    end

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
            termdebug.start(example_path, {
                original_win_id = original_win_id,
                type = DebugType.EXAMPLE,
                name = example_name,
                build_cmd = build_cmd,
            })
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
    -- If there's an active benchmark session, rebuild and reload instead
    local session = termdebug.get_active_session()
    if session and session.type == DebugType.BENCH then
        cargo.rebuild_and_reload()
        return
    end

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
                    termdebug.start(artifact.path, {
                        original_win_id = original_win_id,
                        type = DebugType.BENCH,
                        name = artifact.name,
                    })
                    return
                end
            end
            -- If pinned benchmark not found, notify and continue to selection
            vim.notify("Pinned benchmark '" .. pinned_bench .. "' not found, showing selection...", vim.log.levels.WARN)
        end

        local original_win_id = vim.api.nvim_get_current_win()
        if #bench_artifacts == 1 then
            local artifact = bench_artifacts[1]
            local bin_path = artifact.path
            vim.notify("Debugging benchmark: " .. bin_path, vim.log.levels.INFO)
            termdebug.start(bin_path, {
                original_win_id = original_win_id,
                type = DebugType.BENCH,
                name = artifact.name,
            })
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
                termdebug.start(selected_artifact.path, {
                    original_win_id = original_win_id,
                    type = DebugType.BENCH,
                    name = selected_artifact.name,
                })
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

cargo.rebuild_and_reload = function()
    local session = termdebug.get_active_session()

    if not session then
        vim.notify("No active debug session to reload", vim.log.levels.WARN)
        return
    end

    if session.type == DebugType.BINARY and session.build_cmd then
        -- For binaries, we have a build_cmd we can use
        local profile_info = session.profile and (" (" .. session.profile .. ")") or ""
        vim.notify("Rebuilding binary: " .. session.name .. profile_info, vim.log.levels.INFO)
        run_build(session.build_cmd, function()
            vim.notify("Reloading binary: " .. session.path, vim.log.levels.INFO)
            -- Send file command to reload the binary
            vim.fn.TermDebugSendCommand("file " .. session.path)
            -- Delete all GDB breakpoints
            vim.fn.TermDebugSendCommand("d")
            -- Restore breakpoints from extmarks
            breakpoints.restore_all()
        end)
    elseif session.type == DebugType.TEST then
        -- For tests, rebuild all tests
        vim.notify("Rebuilding tests...", vim.log.levels.INFO)
        cargo.build_tests(function(test_artifacts)
            if not test_artifacts then
                return
            end

            -- Find the matching artifact
            for _, artifact in ipairs(test_artifacts) do
                if artifact.name == session.name then
                    vim.notify("Reloading test: " .. artifact.path, vim.log.levels.INFO)
                    vim.fn.TermDebugSendCommand("file " .. artifact.path)
                    vim.fn.TermDebugSendCommand("d")
                    breakpoints.restore_all()
                    return
                end
            end

            vim.notify("Could not find test artifact: " .. session.name, vim.log.levels.ERROR)
        end)
    elseif session.type == DebugType.EXAMPLE and session.build_cmd then
        -- For examples, we have a build_cmd
        vim.notify("Rebuilding example: " .. session.name, vim.log.levels.INFO)
        run_build(session.build_cmd, function()
            vim.notify("Reloading example: " .. session.path, vim.log.levels.INFO)
            vim.fn.TermDebugSendCommand("file " .. session.path)
            vim.fn.TermDebugSendCommand("d")
            breakpoints.restore_all()
        end)
    elseif session.type == DebugType.BENCH then
        -- For benchmarks, rebuild all benchmarks
        vim.notify("Rebuilding benchmarks...", vim.log.levels.INFO)
        cargo.build_benches(function(bench_artifacts)
            if not bench_artifacts then
                return
            end

            -- Find the matching artifact
            for _, artifact in ipairs(bench_artifacts) do
                if artifact.name == session.name then
                    vim.notify("Reloading benchmark: " .. artifact.path, vim.log.levels.INFO)
                    vim.fn.TermDebugSendCommand("file " .. artifact.path)
                    vim.fn.TermDebugSendCommand("d")
                    breakpoints.restore_all()
                    return
                end
            end

            vim.notify("Could not find benchmark artifact: " .. session.name, vim.log.levels.ERROR)
        end)
    else
        vim.notify("Cannot rebuild session type: " .. tostring(session.type), vim.log.levels.ERROR)
    end
end

return cargo
