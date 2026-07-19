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

    describe("CommandTree:resolve", function()
        local SlashCommandGroup = require("interactions.slash_command_group")

        it("resolves a plain ApplicationCommand and its own checks", function()
            local tree = CommandTree.new(make_http({}))
            local check = { name = "owner", func = function() return true end }
            local cmd = ApplicationCommand.new("ping", "Replies with pong")
            cmd.callback = function() end
            cmd.checks = { check }
            tree:add(cmd)

            local resolved, checks = tree:resolve({
                data = { name = "ping", options = {} },
            })

            assert.equals(cmd, resolved)
            assert.equals(1, #checks)
            assert.equals(check, checks[1])
        end)

        it("returns nil, {} when no command matches", function()
            local tree = CommandTree.new(make_http({}))
            local resolved, checks = tree:resolve({
                data = { name = "missing", options = {} },
            })
            assert.is_nil(resolved)
            assert.same({}, checks)
        end)

        it("resolves a one level subcommand under a group", function()
            local tree = CommandTree.new(make_http({}))
            local group = SlashCommandGroup.new("math", "Math commands")
            local callback = function() end
            group:command("add", "Adds numbers", callback)
            tree:add(group)

            local resolved, _checks = tree:resolve({
                data = {
                    name = "math",
                    options = { { name = "add", type = 1, options = {} } },
                },
            })

            assert.is_not_nil(resolved)
            assert.equals(callback, resolved.callback)
        end)

        it("resolves a two level subcommand under a subgroup", function()
            local tree = CommandTree.new(make_http({}))
            local group = SlashCommandGroup.new("greetings", "Greetings")
            local subgroup = group:create_subgroup("international", "International greetings")
            local callback = function() end
            subgroup:command("aloha", "Says aloha", callback)
            tree:add(group)

            local resolved = tree:resolve({
                data = {
                    name = "greetings",
                    options = {
                        {
                            name = "international",
                            type = 2,
                            options = { { name = "aloha", type = 1, options = {} } },
                        },
                    },
                },
            })

            assert.is_not_nil(resolved)
            assert.equals(callback, resolved.callback)
        end)

        it("collects group checks before the subcommand's own checks", function()
            local tree = CommandTree.new(make_http({}))
            local group_check = { name = "group_check", func = function() return true end }
            local cmd_check = { name = "cmd_check", func = function() return true end }
            local group = SlashCommandGroup.new("math", "Math", { checks = { group_check } })
            local cmd = group:command("add", "Adds numbers", function() end, { checks = { cmd_check } })
            tree:add(group)

            local resolved, checks = tree:resolve({
                data = {
                    name = "math",
                    options = { { name = "add", type = 1, options = {} } },
                },
            })

            assert.equals(cmd, resolved)
            assert.equals(2, #checks)
            assert.equals(group_check, checks[1])
            assert.equals(cmd_check, checks[2])
        end)

        it("returns nil, {} when the subcommand path doesn't resolve", function()
            local tree = CommandTree.new(make_http({}))
            local group = SlashCommandGroup.new("math", "Math commands")
            group:command("add", "Adds numbers", function() end)
            tree:add(group)

            local resolved, checks = tree:resolve({
                data = {
                    name = "math",
                    options = { { name = "subtract", type = 1, options = {} } },
                },
            })

            assert.is_nil(resolved)
            assert.same({}, checks)
        end)
    end)
end)
