require("spec_helper")

local Client = require("./http/client")

describe("HTTP Client interaction callbacks", function()
    it("encodes path and query values and sorts query keys", function()
        local previous_http = package.loaded["coro-http"]
        local received_url
        package.loaded["coro-http"] = {
            request = function(_, url)
                received_url = url
                return { code = 200 }, "{}"
            end,
        }
        local client = Client.new("token")
        client:get("/invites/a b?z=hello world&a=é")
        package.loaded["coro-http"] = previous_http
        assert.equals("https://discord.com/api/v10/invites/a%20b?a=%C3%A9&z=hello%20world", received_url)
    end)

    it("passes coro-http response header pairs to the rate limiter", function()
        local previous_http = package.loaded["coro-http"]
        local received_headers
        package.loaded["coro-http"] = {
            request = function()
                return {
                    code = 200,
                    { "X-RateLimit-Remaining", "4" },
                    { "X-RateLimit-Reset-After", "1.5" },
                    { "Retry-After", "1" },
                }, "{}"
            end,
        }
        local limiter = {
            is_rate_limited = function() return false end,
            update_bucket = function(_, _, headers) received_headers = headers end,
            update_global = function() end,
        }
        Client.new("token", limiter):get("/channels/1/messages")
        package.loaded["coro-http"] = previous_http
        assert.equals("4", received_headers["x-ratelimit-remaining"])
        assert.equals("1.5", received_headers["x-ratelimit-reset-after"])
        assert.equals("1", received_headers["retry-after"])
    end)

    it("keeps major route ids while grouping nested resource ids", function()
        local previous_http = package.loaded["coro-http"]
        package.loaded["coro-http"] = { request = function() return { code = 200 }, "{}" end }
        local keys = {}
        local limiter = {
            is_rate_limited = function() return false end,
            update_bucket = function(_, key) keys[#keys + 1] = key end,
            update_global = function() end,
        }
        local client = Client.new("token", limiter)
        client:get("/channels/10/messages/20")
        client:get("/channels/11/messages/20")
        client:get("/channels/10/messages/21")
        package.loaded["coro-http"] = previous_http
        assert.not_equals(keys[1], keys[2])
        assert.equals(keys[1], keys[3])
    end)
    it("sends an unauthenticated JSON callback request with its configured user agent", function()
        local previous_http = package.loaded["coro-http"]
        local received = nil
        package.loaded["coro-http"] = {
            request = function(method, url, headers, body)
                received = { method = method, url = url, headers = headers, body = body }
                return { code = 204 }, ""
            end,
        }

        local client = Client.new("bot-token")
        client.headers["User-Agent"] = "custom-discord-lua-agent"
        assert.equals("", client:post_interaction_callback("interaction-id", "interaction-token", { type = 8 }))

        package.loaded["coro-http"] = previous_http

        local header_map = {}
        for _, header in ipairs(received.headers) do
            header_map[header[1]] = header[2]
        end
        assert.equals("POST", received.method)
        assert.equals(
            "https://discord.com/api/v10/interactions/interaction-id/interaction-token/callback",
            received.url
        )
        assert.equals("application/json", header_map["Content-Type"])
        assert.equals("custom-discord-lua-agent", header_map["User-Agent"])
        assert.is_nil(header_map["Authorization"])
    end)

    it("keeps bot authorization on ordinary REST requests", function()
        local previous_http = package.loaded["coro-http"]
        local received = nil
        package.loaded["coro-http"] = {
            request = function(method, url, headers, body)
                received = { method = method, url = url, headers = headers, body = body }
                return { code = 200 }, "{}"
            end,
        }

        local client = Client.new("bot-token")
        client:post("/applications/app-id/commands", { name = "play" })

        package.loaded["coro-http"] = previous_http

        local header_map = {}
        for _, header in ipairs(received.headers) do
            header_map[header[1]] = header[2]
        end
        assert.equals("POST", received.method)
        assert.equals("https://discord.com/api/v10/applications/app-id/commands", received.url)
        assert.equals("Bot bot-token", header_map["Authorization"])
        assert.equals("discord.lua", header_map["User-Agent"])
        assert.equals("application/json", header_map["Content-Type"])
    end)
end)
