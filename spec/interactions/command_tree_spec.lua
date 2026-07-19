-- spec/interactions/command_tree_spec.lua
-- Tests for the application command tree: registration, diffing, sync,
-- and autocomplete dispatch.

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local CommandTree = require("interactions.command_tree")
local ApplicationCommand = require("interactions.application_command")

-- Minimal http double recording calls and returning canned responses.
local function make_http(responses)
    local calls = {}
    local http = { calls = calls }

    function http:get(endpoint)
        table.insert(calls, { method = "GET", endpoint = endpoint })
        return responses[endpoint] or {}
    end

    function http:put(endpoint, body)
        table.insert(calls, { method = "PUT", endpoint = endpoint, body = body })
        return body
    end

    return http
end

describe("CommandTree", function()
    it("adds and retrieves a global command by name", function()
        local tree = CommandTree.new(make_http({}))
        local cmd = ApplicationCommand.new("ping", "Replies with pong")
        tree:add(cmd)

        assert.equals(cmd, tree:get("ping"))
        assert.is_nil(tree:get("missing"))
    end)

    it("scopes a command lookup to its guild_ids", function()
        local tree = CommandTree.new(make_http({}))
        local cmd = ApplicationCommand.new("ping", "Replies with pong")
        cmd.guild_ids = { "111" }
        tree:add(cmd)

        assert.equals(cmd, tree:get("ping", "111"))
        assert.is_nil(tree:get("ping", "222"))
        assert.is_nil(tree:get("ping"))
    end)

    it("syncs global commands via PUT when none are registered remotely", function()
        local http = make_http({ ["/applications/1/commands"] = {} })
        local tree = CommandTree.new(http)
        tree:add(ApplicationCommand.new("ping", "Replies with pong"))

        tree:sync("1")

        local put_calls = 0
        for _, call in ipairs(http.calls) do
            if call.method == "PUT" then
                put_calls = put_calls + 1
            end
        end
        assert.equals(1, put_calls)
    end)

    it("skips the PUT when the remote command set already matches", function()
        local remote = {
            { name = "ping", description = "Replies with pong", type = 1 },
        }
        local http = make_http({ ["/applications/1/commands"] = remote })
        local tree = CommandTree.new(http)
        tree:add(ApplicationCommand.new("ping", "Replies with pong"))

        tree:sync("1")

        for _, call in ipairs(http.calls) do
            assert.are_not.equals("PUT", call.method)
        end
    end)

    it("syncs each guild's commands to their own endpoint", function()
        local http = make_http({})
        local tree = CommandTree.new(http)
        local cmd = ApplicationCommand.new("ping", "Replies with pong")
        cmd.guild_ids = { "111" }
        tree:add(cmd)

        tree:sync("1")

        local hit_guild_endpoint = false
        for _, call in ipairs(http.calls) do
            if call.endpoint == "/applications/1/guilds/111/commands" and call.method == "PUT" then
                hit_guild_endpoint = true
            end
        end
        assert.is_true(hit_guild_endpoint)
    end)

    it("dispatches an autocomplete interaction to the focused option's callback", function()
        local tree = CommandTree.new(make_http({}))
        local cmd = ApplicationCommand.new("search", "Search something", {
            { name = "query", type = 3 },
        })

        local received_value
        cmd:set_autocomplete("query", function(ctx)
            received_value = ctx.value
        end)
        tree:add(cmd)

        local handled = tree:dispatch_autocomplete({
            type = 4,
            data = {
                name = "search",
                options = { { name = "query", value = "abc", focused = true } },
            },
        })

        assert.is_true(handled)
        assert.equals("abc", received_value)
    end)

    it("returns false from dispatch_autocomplete when no command matches", function()
        local tree = CommandTree.new(make_http({}))

        local handled = tree:dispatch_autocomplete({
            type = 4,
            data = { name = "missing", options = {} },
        })

        assert.is_false(handled)
    end)
end)
