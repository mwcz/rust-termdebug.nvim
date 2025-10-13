local termdebug = require("termdebug")

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
    if not metadata then
        return
    end
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

    if #priority_bin_list == 1 then
        -- build and debug the one and only binary
        rust_build_and_debug(priority_bin_list[1].name)
    else
        -- choose which binary to build and debug
        local choices = {}
        for _, bin_info in ipairs(priority_bin_list) do
            table.insert(choices, bin_info.name)
        end
        vim.ui.select(choices, { prompt = "Select a binary to debug:" }, function(choice, idx)
            if choice then
                rust_build_and_debug(priority_bin_list[idx].name)
            end
        end)
    end
end

-- Use a session-local variable to store the persisted binary name.
local persisted_binary = nil

cargo.debug_bin = function()
    local metadata = cargo.metadata()
    local target_dir = metadata.target_directory

    local function rust_build_and_debug(target_dir, bin_crate_name)
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

    if persisted_binary then
        rust_build_and_debug(target_dir, persisted_binary)
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

    if #sorted_binaries == 1 then
        -- build and debug the one and only binary
        rust_build_and_debug(target_dir, sorted_binaries[1].name)
    else
        -- choose which binary to build and debug
        local choices = {}
        local persist_suffix = " (persist)"
        for _, bin_info in ipairs(sorted_binaries) do
            table.insert(choices, bin_info.name)
            table.insert(choices, bin_info.name .. persist_suffix)
        end

        vim.ui.select(choices, { prompt = "Select a binary to debug:" }, function(choice)
            if choice then
                local bin_to_debug
                -- Check if the user chose a "persist" option.
                if choice:sub(- #persist_suffix) == persist_suffix then
                    -- Extract the binary name and save it to the session variable.
                    bin_to_debug = choice:sub(1, #choice - #persist_suffix)
                    persisted_binary = bin_to_debug
                    vim.notify("Set " .. bin_to_debug .. " as default for this session.", vim.log.levels.INFO)
                else
                    bin_to_debug = choice
                end
                rust_build_and_debug(target_dir, bin_to_debug)
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

        -- The rest of the logic for selecting and launching the debugger remains the same.
        local original_win_id = vim.api.nvim_get_current_win()
        if #test_artifacts == 1 then
            local bin_path = test_artifacts[1].path
            vim.notify("Debugging test: " .. bin_path, vim.log.levels.INFO)
            termdebug.start(bin_path, original_win_id)
        else
            local choices = {}
            for _, artifact in ipairs(test_artifacts) do
                local kinds = table.concat(artifact.kind, ", ")
                table.insert(choices, "Test module: " .. artifact.name .. " (" .. kinds .. ")")
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
    end)
end

cargo.debug_example = function()
    vim.notify("Finding examples...", vim.log.levels.INFO)

    local metadata = cargo.metadata()
    if not metadata then
        return
    end
    local target_dir = metadata.target_directory

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

    if #examples == 1 then
        build_and_debug_example(examples[1].name)
    else
        local choices = {}
        for _, example in ipairs(examples) do
            table.insert(choices, "Example: " .. example.name)
        end

        vim.ui.select(choices, { prompt = "Select an example to debug:" }, function(choice, idx)
            if choice then
                build_and_debug_example(examples[idx].name)
            else
                vim.notify("Debugger launch cancelled.", vim.log.levels.INFO)
            end
        end)
    end
end

cargo.debug_process = function()
    vim.notify("Searching for running processes...", vim.log.levels.INFO)

    local process_lines = vim.fn.systemlist("ps -eo pid,args --no-headers")

    if not process_lines or #process_lines == 0 then
        vim.notify("Could not find any running processes.", vim.log.levels.WARN)
        return
    end

    vim.ui.select(process_lines, { prompt = "Select process to attach to:" }, function(selected_process)
        if not selected_process then
            vim.notify("Attach cancelled.", vim.log.levels.INFO)
            return
        end

        local parts = vim.split(vim.trim(selected_process), "%s+", { trimempty = true })
        local pid = parts[1]
        local program_path = parts[2]

        if not pid or not program_path then
            vim.notify("Could not parse PID and program path from selection.", vim.log.levels.ERROR)
            return
        end

        vim.notify("Attaching to PID: " .. pid .. " (" .. program_path .. ")", vim.log.levels.INFO)

        local original_win_id = vim.api.nvim_get_current_win()
        termdebug.start(nil, original_win_id)

        vim.defer_fn(function()
            vim.fn.TermDebugSendCommand("attach " .. pid)
            vim.notify("Attached to process. Use 'continue' in GDB to resume.", vim.log.levels.INFO)
        end, 100)
    end)
end

return cargo
