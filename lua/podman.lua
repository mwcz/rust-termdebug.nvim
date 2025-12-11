local options = require("options")

local podman = {}

-- Find an unused port in the ephemeral port range
-- Returns: port number
podman.find_unused_port = function()
    -- Use ephemeral port range (49152-65535)
    local min_port = 49152
    local max_port = 65535

    -- Try up to 100 random ports
    for _ = 1, 100 do
        local port = math.random(min_port, max_port)

        -- Check if port is in use using netstat/ss
        -- We check both TCP and TCP6 since containers can use either
        local check_cmd = string.format(
            "ss -ln '( sport = :%d )' 2>/dev/null | grep -q LISTEN || echo available",
            port
        )
        local result = vim.fn.system(check_cmd)

        if vim.trim(result) == "available" then
            return port
        end
    end

    -- Fallback to a random port if we couldn't find one
    -- Let the OS potentially reject it if it's in use
    return math.random(min_port, max_port)
end

-- Build a map of all PIDs to their container info efficiently
-- This is much faster than checking each PID individually
-- Returns: table mapping host PID (string) to { name = string, id = string, container_pid = string }
podman.build_pid_to_container_map = function()
    local pid_to_container = {}

    -- Get all running containers
    local cmd = "podman ps --format '{{.ID}}|{{.Names}}' 2>/dev/null"
    local containers = vim.fn.systemlist(cmd)

    if vim.v.shell_error ~= 0 or not containers or #containers == 0 then
        return pid_to_container -- No containers running
    end

    -- For each container, get all its PIDs
    for _, line in ipairs(containers) do
        local parts = vim.split(line, "|")
        if #parts >= 2 then
            local container_id = parts[1]
            local container_name = parts[2]

            -- Get both host PIDs and container PIDs
            -- We need both to map host PID -> container PID for gdbserver
            local top_cmd = string.format("podman top %s hpid pid 2>/dev/null | tail -n +2", vim.fn.shellescape(container_id))
            local pid_lines = vim.fn.systemlist(top_cmd)

            if vim.v.shell_error == 0 and pid_lines then
                for _, pid_line in ipairs(pid_lines) do
                    local pid_parts = vim.split(vim.trim(pid_line), "%s+", { trimempty = true })
                    if #pid_parts >= 2 then
                        local host_pid = pid_parts[1]
                        local container_pid = pid_parts[2]

                        if host_pid:match("^%d+$") and container_pid:match("^%d+$") then
                            pid_to_container[host_pid] = {
                                name = container_name,
                                id = container_id,
                                container_pid = container_pid,
                            }
                        end
                    end
                end
            end
        end
    end

    return pid_to_container
end

-- Detect if a PID is running inside a podman container
-- Returns: { name = container_name, id = container_id } or nil
podman.detect_container_for_pid = function(pid)
    if not pid then
        return nil
    end

    -- Get all running containers with their PIDs
    -- Format: CONTAINER_ID|NAMES|PIDs (comma-separated)
    local cmd = "podman ps --format '{{.ID}}|{{.Names}}|{{.Pid}}' 2>/dev/null"
    local containers = vim.fn.systemlist(cmd)

    if vim.v.shell_error ~= 0 or not containers or #containers == 0 then
        return nil
    end

    -- Check each container to see if our PID is in its PID namespace
    for _, line in ipairs(containers) do
        local parts = vim.split(line, "|")
        if #parts >= 3 then
            local container_id = parts[1]
            local container_name = parts[2]
            local container_main_pid = parts[3]

            -- Get all PIDs in this container's namespace
            -- We check if our target PID is in the same PID namespace as the container
            local ns_check = string.format(
                "readlink /proc/%s/ns/pid 2>/dev/null | grep -q \"$(readlink /proc/%s/ns/pid 2>/dev/null)\" && echo yes || echo no",
                pid,
                container_main_pid
            )
            local result = vim.fn.system(ns_check)

            if vim.trim(result) == "yes" then
                return {
                    name = container_name,
                    id = container_id,
                }
            end
        end
    end

    return nil
end

-- Check if gdbserver exists in the container
-- Returns: true if gdbserver is found, false otherwise
podman.has_gdbserver = function(container_name)
    local cmd = string.format("podman exec %s which gdbserver 2>/dev/null", vim.fn.shellescape(container_name))
    local result = vim.fn.system(cmd)
    return vim.v.shell_error == 0 and vim.trim(result) ~= ""
end

-- Try to install gdbserver in container using package manager
-- Returns: true on success, false on failure
local function install_gdbserver_in_container(container_name)
    -- Try different package managers in order
    local package_managers = {
        { cmd = "dnf", pkg = "gdb-gdbserver", install = "dnf install -y gdb-gdbserver" },
        { cmd = "yum", pkg = "gdb-gdbserver", install = "yum install -y gdb-gdbserver" },
        { cmd = "apt-get", pkg = "gdbserver", install = "apt-get update && apt-get install -y gdbserver" },
        { cmd = "apk", pkg = "gdb", install = "apk add --no-cache gdb" },
    }

    for _, pm in ipairs(package_managers) do
        -- Check if this package manager exists in the container
        local check_cmd = string.format(
            "podman exec %s which %s 2>/dev/null",
            vim.fn.shellescape(container_name),
            pm.cmd
        )
        local result = vim.fn.system(check_cmd)

        if vim.v.shell_error == 0 and vim.trim(result) ~= "" then
            -- This package manager exists, try to install
            vim.notify(
                string.format("Installing gdbserver in container '%s' using %s...", container_name, pm.cmd),
                vim.log.levels.INFO
            )

            local install_cmd = string.format(
                "podman exec %s sh -c %s 2>&1",
                vim.fn.shellescape(container_name),
                vim.fn.shellescape(pm.install)
            )

            local output = vim.fn.system(install_cmd)

            if vim.v.shell_error == 0 then
                vim.notify(
                    string.format("Successfully installed gdbserver in container '%s'", container_name),
                    vim.log.levels.INFO
                )
                return true
            else
                vim.notify(
                    string.format("Failed to install gdbserver using %s: %s", pm.cmd, output),
                    vim.log.levels.WARN
                )
            end
        end
    end

    return false
end

-- Inject gdbserver into a container by copying from host or installing
-- Returns: true on success, false on failure
podman.inject_gdbserver = function(container_name)
    if not container_name then
        return false
    end

    -- First check if container already has gdbserver
    if podman.has_gdbserver(container_name) then
        vim.notify(
            string.format("Container '%s' already has gdbserver installed", container_name),
            vim.log.levels.INFO
        )
        return true
    end

    -- Try to copy from host if available
    local host_gdbserver = vim.fn.system("which gdbserver 2>/dev/null")
    if vim.v.shell_error == 0 and vim.trim(host_gdbserver) ~= "" then
        host_gdbserver = vim.trim(host_gdbserver)

        vim.notify(
            string.format("Copying gdbserver from host to container '%s'...", container_name),
            vim.log.levels.INFO
        )

        local copy_cmd = string.format(
            "podman cp %s %s:/tmp/gdbserver 2>&1",
            vim.fn.shellescape(host_gdbserver),
            vim.fn.shellescape(container_name)
        )

        local output = vim.fn.system(copy_cmd)

        if vim.v.shell_error == 0 then
            -- Make it executable
            local chmod_cmd = string.format(
                "podman exec %s chmod +x /tmp/gdbserver",
                vim.fn.shellescape(container_name)
            )
            vim.fn.system(chmod_cmd)

            if vim.v.shell_error == 0 then
                vim.notify(
                    string.format("Successfully copied gdbserver to container '%s'", container_name),
                    vim.log.levels.INFO
                )
                return true
            else
                vim.notify("Failed to make gdbserver executable, trying installation instead...", vim.log.levels.WARN)
            end
        else
            vim.notify(
                string.format("Failed to copy gdbserver, trying installation instead: %s", output),
                vim.log.levels.WARN
            )
        end
    end

    -- Fallback: try to install gdbserver in the container
    vim.notify(
        string.format("Host doesn't have gdbserver, attempting to install in container '%s'...", container_name),
        vim.log.levels.INFO
    )

    if install_gdbserver_in_container(container_name) then
        return true
    end

    -- Final failure
    vim.notify(
        string.format(
            "Failed to inject gdbserver into container '%s'. Install gdb-gdbserver on host or in container manually.",
            container_name
        ),
        vim.log.levels.ERROR
    )
    return false
end

-- Get the IP address or connection target for a container
-- Returns: IP address string or "localhost" for host networking
podman.get_container_ip = function(container_name)
    -- First, check the network mode
    local network_mode_cmd = string.format(
        "podman inspect -f '{{.HostConfig.NetworkMode}}' %s 2>/dev/null",
        vim.fn.shellescape(container_name)
    )
    local network_mode = vim.fn.system(network_mode_cmd)
    network_mode = vim.trim(network_mode)

    -- If using host networking, use localhost
    if network_mode == "host" then
        vim.notify("Container is using host networking, connecting to localhost", vim.log.levels.INFO)
        return "localhost"
    end

    -- Try to get the IP address from NetworkSettings
    local ip_cmd = string.format(
        "podman inspect -f '{{.NetworkSettings.IPAddress}}' %s 2>/dev/null",
        vim.fn.shellescape(container_name)
    )
    local ip = vim.fn.system(ip_cmd)
    ip = vim.trim(ip)

    if ip ~= "" and ip ~= "<no value>" then
        return ip
    end

    -- Try to get IP from Networks (for containers in custom networks)
    local networks_ip_cmd = string.format(
        "podman inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' %s 2>/dev/null",
        vim.fn.shellescape(container_name)
    )
    local networks_ip = vim.fn.system(networks_ip_cmd)
    networks_ip = vim.trim(networks_ip)

    if networks_ip ~= "" and networks_ip ~= "<no value>" then
        return networks_ip
    end

    -- Last resort: try localhost (for slirp4netns or other special networking)
    vim.notify(
        "Could not determine container IP, will try localhost (this may work for some network modes)",
        vim.log.levels.WARN
    )
    return "localhost"
end

-- Start gdbserver in a container attached to a specific PID
-- Returns: true on success, false on failure
podman.start_gdbserver_in_container = function(container_name, pid, port)
    if not container_name or not pid or not port then
        return false
    end

    -- Determine which gdbserver to use
    local gdbserver_path = "/tmp/gdbserver"
    if podman.has_gdbserver(container_name) then
        -- Use the system gdbserver if available
        local which_result = vim.fn.system(
            string.format("podman exec %s which gdbserver 2>/dev/null", vim.fn.shellescape(container_name))
        )
        if vim.v.shell_error == 0 and vim.trim(which_result) ~= "" then
            gdbserver_path = vim.trim(which_result)
        end
    end

    -- Start gdbserver in background
    -- Using nohup to keep it running even if the exec session ends
    local gdbserver_cmd = string.format(
        "podman exec -d %s %s :%d --attach %s",
        vim.fn.shellescape(container_name),
        gdbserver_path,
        port,
        pid
    )

    vim.notify(
        string.format("Starting gdbserver in container '%s' on port %d...", container_name, port),
        vim.log.levels.INFO
    )

    local output = vim.fn.system(gdbserver_cmd)

    if vim.v.shell_error ~= 0 then
        vim.notify(
            string.format("Failed to start gdbserver: %s", output),
            vim.log.levels.ERROR
        )
        return false
    end

    -- Give gdbserver a moment to attach
    vim.wait(500)

    return true
end

-- Format a suffix for the process list UI
-- Returns: string suffix to append to process line
podman.format_process_suffix = function(container_info)
    if not container_info then
        return ""
    end

    local suffix = string.format(" [podman:%s]", container_info.name)

    if options.current.podman.inject_gdbserver then
        suffix = suffix .. " (will inject gdbserver)"
    end

    return suffix
end

-- Attach to a process in a container using gdbserver
-- This is the main entry point for container debugging
-- pid: host PID (the one from ps output)
-- container_info: table with name, id, and container_pid fields
podman.debug_attach_container = function(pid, container_info, termdebug_module)
    if not pid or not container_info then
        vim.notify("Invalid container debugging parameters", vim.log.levels.ERROR)
        return false
    end

    local container_name = container_info.name
    local container_pid = container_info.container_pid

    if not container_pid then
        vim.notify(
            string.format("Could not determine container-internal PID for host PID %s", pid),
            vim.log.levels.ERROR
        )
        return false
    end

    -- Determine port: either use specified port or find an unused one
    local port_config = options.current.podman.gdbserver_port
    local port

    if port_config == "auto" then
        port = podman.find_unused_port()
        vim.notify(
            string.format("Using automatically selected port %d for gdbserver", port),
            vim.log.levels.INFO
        )
    elseif type(port_config) == "number" then
        port = port_config
    else
        -- Default fallback
        port = 2345
    end

    -- Step 1: Inject gdbserver if configured and not already present
    if options.current.podman.inject_gdbserver then
        if not podman.inject_gdbserver(container_name) then
            return false
        end
    else
        -- Check if gdbserver is available
        if not podman.has_gdbserver(container_name) then
            vim.notify(
                string.format(
                    "Container '%s' does not have gdbserver. Enable podman.inject_gdbserver in config.",
                    container_name
                ),
                vim.log.levels.ERROR
            )
            return false
        end
    end

    -- Step 2: Kill any existing gdbserver instances in the container
    -- Find gdbserver processes using podman top and kill them from the host
    local gdbserver_pids_cmd = string.format(
        "podman top %s hpid args 2>/dev/null | grep gdbserver | awk '{print $1}'",
        vim.fn.shellescape(container_name)
    )
    local gdbserver_pids = vim.fn.systemlist(gdbserver_pids_cmd)

    if gdbserver_pids and #gdbserver_pids > 0 then
        vim.notify("Cleaning up existing gdbserver instances...", vim.log.levels.INFO)

        for _, host_pid in ipairs(gdbserver_pids) do
            host_pid = vim.trim(host_pid)
            if host_pid ~= "" and host_pid:match("^%d+$") then
                -- Kill from the host side (container may not have kill command)
                vim.fn.system(string.format("kill -9 %s 2>/dev/null", host_pid))
            end
        end

        -- Give the process time to be released from tracing
        vim.wait(200)
    end

    -- Step 3: Determine connection method based on network mode
    local network_mode_cmd = string.format(
        "podman inspect -f '{{.HostConfig.NetworkMode}}' %s 2>/dev/null",
        vim.fn.shellescape(container_name)
    )
    local network_mode = vim.trim(vim.fn.system(network_mode_cmd))

    -- Step 4: Start termdebug without a binary
    local original_win_id = vim.api.nvim_get_current_win()
    termdebug_module.start(nil, { original_win_id = original_win_id })

    vim.defer_fn(function()
        if network_mode == "host" then
            -- Host networking: use TCP connection to localhost
            vim.notify(
                string.format("Starting gdbserver for container PID %s (host PID %s)", container_pid, pid),
                vim.log.levels.INFO
            )

            if not podman.start_gdbserver_in_container(container_name, container_pid, port) then
                vim.notify("Failed to start gdbserver", vim.log.levels.ERROR)
                return
            end

            vim.wait(500)

            local target = string.format("localhost:%d", port)
            vim.fn.TermDebugSendCommand("target remote " .. target)
            vim.notify(
                string.format("Connected to gdbserver at %s. Process is paused.", target),
                vim.log.levels.INFO
            )
        else
            -- Bridge or other networking: use stdio mode via podman exec
            vim.notify(
                string.format(
                    "Container uses %s networking, using stdio mode for gdbserver (PID %s)",
                    network_mode,
                    container_pid
                ),
                vim.log.levels.INFO
            )

            -- Determine which gdbserver to use
            local gdbserver_path = "/usr/bin/gdbserver"
            if podman.has_gdbserver(container_name) then
                local which_result = vim.fn.system(
                    string.format("podman exec %s which gdbserver 2>/dev/null", vim.fn.shellescape(container_name))
                )
                if vim.v.shell_error == 0 and vim.trim(which_result) ~= "" then
                    gdbserver_path = vim.trim(which_result)
                end
            elseif vim.fn.filereadable(string.format("/proc/%s/root/tmp/gdbserver", pid)) == 1 then
                gdbserver_path = "/tmp/gdbserver"
            end

            -- Use stdio mode: target remote | podman exec -i container gdbserver - --attach PID
            local remote_cmd = string.format(
                "podman exec -i %s %s - --attach %s",
                vim.fn.shellescape(container_name),
                gdbserver_path,
                container_pid
            )

            vim.fn.TermDebugSendCommand("target remote | " .. remote_cmd)
            vim.notify(
                string.format("Connected to gdbserver via stdio. Process is paused."),
                vim.log.levels.INFO
            )
        end
    end, 500)

    return true
end

return podman
