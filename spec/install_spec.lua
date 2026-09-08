describe("native bundle installer", function()
    it("downloads Linux bundles with coro-http instead of curl", function()
        local old_ffi = package.loaded.ffi
        local old_http = package.loaded["coro-http"]
        local old_preload = package.preload["coro-channel"]
        local old_execute = os.execute
        local old_tmpname = os.tmpname

        local archive = "spec/install-download.tmp"
        local command
        package.loaded.ffi = { os = "Linux", arch = "x64" }
        package.loaded["coro-http"] = {
            request = function(method, url)
                assert.equals("GET", method)
                assert.is_not_nil(url:match("discord%-bundle%-linux%-x64%.tar%.xz"))
                return { code = 200 }, "archive"
            end,
        }
        package.preload["coro-channel"] = nil
        os.tmpname = function() return archive end
        os.execute = function(value)
            command = value
            return true
        end

        local ok, err = pcall(function()
            assert(loadfile("install.lua"))()
        end)
        local channel_preload = package.preload["coro-channel"]

        package.loaded.ffi = old_ffi
        package.loaded["coro-http"] = old_http
        package.preload["coro-channel"] = old_preload
        os.execute = old_execute
        os.tmpname = old_tmpname

        local file = io.open(archive, "rb")
        local body = file and file:read("*a")
        if file then file:close() end
        os.remove(archive)

