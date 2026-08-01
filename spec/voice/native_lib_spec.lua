-- spec/voice/native_lib_spec.lua
-- Tests for lib/voice/native_lib.lua's bundled dll path resolution.

require("spec_helper")

describe("native_lib", function()
    local real_ffi = package.loaded["ffi"]

    local function reload_native_lib()
        package.loaded["./voice/native_lib"] = nil
        return require("./voice/native_lib")
    end

    after_each(function()
        package.loaded["ffi"] = real_ffi
        package.loaded["./voice/native_lib"] = nil
    end)

    it("returns nil when ffi is unavailable", function()
        package.loaded["ffi"] = nil
        package.preload["ffi"] = nil

        local native_lib = reload_native_lib()
        assert.is_nil(native_lib.resolve("opus"))
    end)

    it("returns nil on non-Windows platforms", function()
        package.loaded["ffi"] = { os = "Linux", arch = "x64" }

        local native_lib = reload_native_lib()
        assert.is_nil(native_lib.resolve("opus"))
    end)

    it("returns nil on Windows when the arch has no known dll suffix", function()
        package.loaded["ffi"] = { os = "Windows", arch = "mips" }

        local native_lib = reload_native_lib()
        assert.is_nil(native_lib.resolve("opus"))
    end)

    it("returns nil on Windows when the matching dll file does not exist", function()
        package.loaded["ffi"] = { os = "Windows", arch = "x64" }

        local native_lib = reload_native_lib()
        assert.is_nil(native_lib.resolve("nonexistent_lib_xyz"))
    end)

    it("resolves an absolute path ending in the expected filename on Windows/x64", function()
        package.loaded["ffi"] = { os = "Windows", arch = "x64" }

        local native_lib = reload_native_lib()

        local tmp_dir = "lib/voice/dlls"
        os.execute("mkdir -p " .. tmp_dir)
        local f = io.open(tmp_dir .. "/opus-x64.dll", "wb")
        f:write("stub")
        f:close()

        local path = native_lib.resolve("opus")

        os.remove(tmp_dir .. "/opus-x64.dll")

        assert.is_not_nil(path)
        assert.is_not_nil(path:match("opus%-x64%.dll$"))
    end)

    it("maps LuaJIT arch names to the MSVC-style dll suffixes", function()
        local cases = {
            { arch = "x86", suffix = "Win32" },
            { arch = "x64", suffix = "x64" },
            { arch = "arm64", suffix = "ARM64" },
        }

        for _, case in ipairs(cases) do
            package.loaded["ffi"] = { os = "Windows", arch = case.arch }
            local native_lib = reload_native_lib()

            local tmp_dir = "lib/voice/dlls"
            os.execute("mkdir -p " .. tmp_dir)
            local filename = "libsodium-" .. case.suffix .. ".dll"
            local f = io.open(tmp_dir .. "/" .. filename, "wb")
            f:write("stub")
            f:close()

            local path = native_lib.resolve("libsodium")

            os.remove(tmp_dir .. "/" .. filename)

            assert.is_not_nil(path, "expected a resolved path for arch " .. case.arch)
            assert.equals(tmp_dir .. "/" .. filename, path)
        end
    end)
end)
