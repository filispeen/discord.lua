-- Tests for lib/voice/native_lib.lua's bundled native path resolution.

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

    it("returns nil on Linux when the requested shared library is absent", function()
        package.loaded["ffi"] = { os = "Linux", arch = "x64" }

        local native_lib = reload_native_lib()
        assert.is_nil(native_lib.resolve("nonexistent_lib_xyz"))
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

    it("resolves an absolute bundled libsodium path on Windows/x64", function()
        package.loaded["ffi"] = { os = "Windows", arch = "x64" }

        local native_lib = reload_native_lib()
        local path = native_lib.resolve("libsodium")

        assert.is_not_nil(path)
        assert.is_not_nil(path:match("libsodium%-x64%.dll$"))
    end)

    it("resolves the bundled Windows x64 library", function()
        package.loaded["ffi"] = { os = "Windows", arch = "x64" }

        local native_lib = reload_native_lib()
        assert.equals("lib/bundle/windows-x64/dll/libsodium-x64.dll", native_lib.resolve("libsodium"))
    end)

    it("returns a PATH override for bundled Windows executables", function()
        package.loaded["ffi"] = { os = "Windows", arch = "x64" }

        local native_lib = reload_native_lib()
        local env = native_lib.windows_dll_env()

        assert.is_not_nil(env)
        assert.is_not_nil(env[1]:match("^PATH=lib/bundle/windows%-x64/dll;"))
    end)

    it("resolves the bundled libsodium path on Linux/x64", function()
        package.loaded["ffi"] = { os = "Linux", arch = "x64" }

        local native_lib = reload_native_lib()
        local path = native_lib.resolve("libsodium")

        assert.is_not_nil(path)
        assert.is_not_nil(path:match("lib/bundle/linux%-x64/lib/libsodium%.so$"))
    end)

    it("resolves the bundled libopus path on Linux/x64", function()
        package.loaded["ffi"] = { os = "Linux", arch = "x64" }

        local native_lib = reload_native_lib()
        local path = native_lib.resolve_opus()

        assert.is_not_nil(path)
        assert.is_not_nil(path:match("lib/bundle/linux%-x64/lib/libopus%.so$"))
    end)

    it("resolves the bundled libdave path on Linux/x64", function()
        package.loaded["ffi"] = { os = "Linux", arch = "x64" }

        local native_lib = reload_native_lib()
        local path = native_lib.resolve_any_platform("libdave")

        assert.is_not_nil(path)
        assert.is_not_nil(path:match("lib/bundle/linux%-x64/lib/libdave%.so$"))
    end)

    it("resolves bundled Linux executables", function()
        package.loaded["ffi"] = { os = "Linux", arch = "x64" }

        local native_lib = reload_native_lib()
        assert.equals("lib/bundle/linux-x64/bin/ffmpeg", native_lib.resolve_executable("ffmpeg"))
        assert.equals("lib/bundle/linux-x64/bin/ffprobe", native_lib.resolve_executable("ffprobe"))
    end)
end)