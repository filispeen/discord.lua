-- Shared helper for locating prebuilt native FFI libraries shipped in
-- lib/bundle/ alongside this package.
--
-- Windows DLLs are grouped in lib/bundle/windows-x64/dll/. Linux x64
-- libraries are grouped in lib/bundle/linux-x64/lib/. Callers fall back to
-- the system loader when no matching bundle is available.

local ffi_ok, ffi = pcall(require, "ffi")
if not ffi_ok then
    ffi = nil
end

local ARCH_SUFFIX = {
    x86 = "Win32",
    x64 = "x64",
    arm64 = "ARM64",
}

local OPUS_ARCH_SUFFIX = {
    x86 = "x86",
    x64 = "x64",
}

local PLATFORM_DIRS = {
    Windows = { x64 = "windows-x64" },
    Linux = { x64 = "linux-x64" },
}

local function file_exists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

local function this_dir()
    local info = debug.getinfo(1, "S")
    local source = info and info.source
    if not source or source:sub(1, 1) ~= "@" then
        return nil
    end

    local path = source:sub(2)
    local dir = path:match("^(.*)[/\\][^/\\]+$")
    if not dir then
        return nil
    end

    return dir:match("^(.*)[/\\][^/\\]+$") or dir
end

local function windows_dll_dir()
    local dir = this_dir()
    if not dir then
        return nil
    end
    return dir .. "/bundle/windows-x64/dll"
end

-- Returns a bundled shared-library path for libsodium or libdave.
local function resolve(base_name)
    if not ffi_ok then
        return nil
    end

    local os_ok, os_name = pcall(function() return ffi.os end)
    if not os_ok then
        return nil
    end

    local arch_ok, arch_name = pcall(function() return ffi.arch end)
    if not arch_ok or not arch_name then
        return nil
    end

    local dir = this_dir()
    if not dir then
        return nil
    end

    if os_name == "Linux" then
        local platform_dir = PLATFORM_DIRS.Linux[arch_name]
        if not platform_dir then
            return nil
        end

        local path = dir .. "/bundle/" .. platform_dir .. "/lib/" .. base_name .. ".so"
        if file_exists(path) then
            return path
        end

        local legacy_path = dir .. "/bundle/" .. base_name .. ".so"
        if file_exists(legacy_path) then
            return legacy_path
        end

        return nil
    end

    if os_name ~= "Windows" then
        return nil
    end

    local suffix = ARCH_SUFFIX[arch_name]
    if not suffix then
        return nil
    end

    local dll_dir = windows_dll_dir()
    local path = dll_dir and dll_dir .. "/" .. base_name .. "-" .. suffix .. ".dll" or nil
    if path and file_exists(path) then
        return path
    end

    return nil
end

local function resolve_any_platform(base_name)
    return resolve(base_name)
end

-- Returns the bundled Opus library. Its Windows name differs from libsodium,
-- while Linux uses the standard libopus.so name.
local function resolve_opus()
    if not ffi_ok then
        return nil
    end

    local os_ok, os_name = pcall(function() return ffi.os end)
    if not os_ok then
        return nil
    end

    if os_name == "Linux" then
        return resolve("libopus")
    end

    if os_name ~= "Windows" then
        return nil
    end

    local arch_ok, arch_name = pcall(function() return ffi.arch end)
    local suffix = arch_ok and OPUS_ARCH_SUFFIX[arch_name] or nil
    if not suffix then
        return nil
    end

    local dll_dir = windows_dll_dir()
    local path = dll_dir and dll_dir .. "/libopus-0." .. suffix .. ".dll" or nil
    if path and file_exists(path) then
        return path
    end

    return nil
end

-- Returns an env table for libuv spawn when a bundled Windows executable
-- needs the sibling DLL directory. The complete existing PATH is retained.
local function windows_dll_env()
    if not ffi_ok then
        return nil
    end

    local os_ok, os_name = pcall(function() return ffi.os end)
    if not os_ok or os_name ~= "Windows" then
        return nil
    end

    local dll_dir = windows_dll_dir()
    if not dll_dir or not file_exists(dll_dir .. "/libopus-0.x64.dll") then
        return nil
    end

    return { "PATH=" .. dll_dir .. ";" .. (os.getenv("PATH") or "") }
end

-- Returns a bundled executable path for the current platform. Callers fall
-- back to PATH when this returns nil, preserving explicit overrides.
local function resolve_executable(base_name)
    if not ffi_ok then
        return nil
    end

    local os_ok, os_name = pcall(function() return ffi.os end)
    if not os_ok or (os_name ~= "Windows" and os_name ~= "Linux") then
        return nil
    end

    local dir = this_dir()
    if not dir then
        return nil
    end

    local extension = os_name == "Windows" and ".exe" or ""
    local arch_ok, arch_name = pcall(function() return ffi.arch end)
    local platform_dir = arch_ok and PLATFORM_DIRS[os_name][arch_name] or nil
    if platform_dir then
        local path = dir .. "/bundle/" .. platform_dir .. "/bin/" .. base_name .. extension
        if file_exists(path) then
            return path
        end
    end

    local legacy_path = dir .. "/bundle/" .. base_name .. extension
    if file_exists(legacy_path) then
        return legacy_path
    end

    return nil
end

return {
    resolve = resolve,
    resolve_any_platform = resolve_any_platform,
    resolve_opus = resolve_opus,
    windows_dll_env = windows_dll_env,
    resolve_executable = resolve_executable,
}