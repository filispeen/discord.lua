-- lib/voice/native_lib.lua
-- Shared helper for locating prebuilt native (FFI) libraries shipped in
-- lib/dlls/ alongside this package, used by crypto.lua (libsodium) and
-- opus.lua (libopus).
--
-- Context: package.lua bundles "lib/**.dll" into the published lit
-- package (see .github/workflows/lit-publish.yml, which builds
-- libsodium-<arch>.dll and opus-<arch>.dll into lib/dlls/), but a plain
-- ffi.load("sodium") / ffi.load("opus") only searches the OS's normal
-- library search path (PATH, System32, cwd on Windows; the dynamic
-- linker's search path on Linux/macOS). It never automatically finds
-- lib/dlls/ unless that directory happens to already be on PATH, so the
-- bundled Windows dlls were silently unused. This module resolves an
-- absolute path to the matching bundled dll (Windows only; Linux/macOS
-- are expected to have libsodium/libopus installed as system packages)
-- so ffi.load can be pointed at it directly.
--
-- Public Contract:
--   native_lib.resolve(base_name) -> absolute_path (string) or nil
--     base_name: "libsodium" or "opus", matching the lib/dlls/ naming
--     used by lit-publish.yml (libsodium-<arch>.dll, opus-<arch>.dll).
--     Returns nil on non-Windows platforms, if ffi is unavailable, if
--     jit.os/jit.arch can't be read, or if no matching file exists on
--     disk; callers should fall back to a bare ffi.load(name) in every
--     nil case.
--   native_lib.resolve_any_platform(base_name) -> absolute_path (string) or nil
--     Same as resolve(), but also checks lib/dlls/ on Linux/macOS, since
--     libdave (unlike libsodium/libopus) is not expected to be available
--     as a system package on any platform. base_name: "libdave", looks
--     for lib/dlls/<base_name>-<arch>.dll on Windows (same as resolve())
--     and lib/dlls/<base_name>.so on Linux (no per-arch suffix, since
--     only x64 is currently bundled; see lib/dlls/libdave.so and the
--     v1.1.1 release assets it was copied from,
--     github.com/discord/libdave/releases). macOS is not bundled and
--     always falls through to nil here.

local ffi_ok, ffi = pcall(require, "ffi")
if not ffi_ok then
    ffi = nil
end

-- MSVC-style architecture suffixes used when lit-publish.yml built the
-- bundled dlls, keyed by LuaJIT's jit.arch (see
-- https://luajit.org/ext_jit.html: "x86", "x64", "arm64").
local ARCH_SUFFIX = {
    x86 = "Win32",
    x64 = "x64",
    arm64 = "ARM64",
}

local function file_exists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

-- Directory this module was loaded from, e.g. "lib/voice" when required
-- as "./native_lib" from lib/voice/opus.lua. debug.getinfo mirrors what
-- spec/spec_helper.lua's relative_searcher already relies on to resolve
-- "./x" requires, so this stays correct under luvit, plain lua5.1, and
-- LuaJIT alike.
-- Package root's dlls/ dir. this_dir() gives lib/voice (where this
-- module lives), but the bundled dlls live one level up in lib/dlls/
-- (see lit-publish.yml), not lib/voice/dlls/.
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

-- base_name: "libsodium" or "opus"
local function resolve(base_name)
    if not ffi_ok then
        return nil
    end

    local os_ok, os_name = pcall(function() return ffi.os end)
    if not os_ok or os_name ~= "Windows" then
        return nil
    end

    local arch_ok, arch_name = pcall(function() return ffi.arch end)
    if not arch_ok or not arch_name then
        return nil
    end

    local suffix = ARCH_SUFFIX[arch_name]
    if not suffix then
        return nil
    end

    local dir = this_dir()
    if not dir then
        return nil
    end

    local path = dir .. "/dlls/" .. base_name .. "-" .. suffix .. ".dll"
    if file_exists(path) then
        return path
    end

    return nil
end

-- Linux-only counterpart to resolve() for libraries that are never
-- expected to be installed system-wide (currently just libdave). Only
-- handles the single bundled lib/dlls/<base_name>.so, no per-arch
-- suffix, since only x64 is bundled today.
local function resolve_linux_so(base_name)
    if not ffi_ok then
        return nil
    end

    local os_ok, os_name = pcall(function() return ffi.os end)
    if not os_ok or os_name ~= "Linux" then
        return nil
    end

    local dir = this_dir()
    if not dir then
        return nil
    end

    local path = dir .. "/dlls/" .. base_name .. ".so"
    if file_exists(path) then
        return path
    end

    return nil
end

local function resolve_any_platform(base_name)
    local windows_path = resolve(base_name)
    if windows_path then
        return windows_path
    end

    return resolve_linux_so(base_name)
end

return {
    resolve = resolve,
    resolve_any_platform = resolve_any_platform,
}
