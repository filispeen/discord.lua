-- spec/ext/bridge/bridge_group_spec.lua
-- Tests for BridgeGroup

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local Bot = require("commands.bot")

describe("BridgeGroup", function()
    it("registers a slash command group on the bot", function()
        local bot = Bot.new("token")
        local group = bot:bridge_group("math", { description = "Math commands" })

        assert.equals(group.slash_group, bot.command_tree:get("math"))
    end)

    it("command registers both a prefix command and a slash subcommand", function()
        local bot = Bot.new("token")
        local group = bot:bridge_group("math")
        local invoked_prefix, invoked_app = false, false

        group:command("add", {
            description = "Adds numbers",
            callback = function(ctx)
                if ctx.is_app then
                    invoked_app = true
                else
                    invoked_prefix = true
                end
            end,
        })

        bot:dispatch_message({ content = "!math add", author = { id = "1" } })
        assert.is_true(invoked_prefix)

        bot:dispatch_interaction({
            type = 2,
            data = {
                name = "math",
                options = { { name = "add", type = 1, options = {} } },
            },
            user = { id = "1" },
        })
        assert.is_true(invoked_app)
    end)

    it("map_to exposes the group's bare callback as a named slash subcommand", function()
        local bot = Bot.new("token")
        local invoked = false
        local group = bot:bridge_group("specialcmd", {
            callback = function(_ctx) invoked = true end,
        })
        group:map_to("help")

        bot:dispatch_interaction({
            type = 2,
            data = {
                name = "specialcmd",
                options = { { name = "help", type = 1, options = {} } },
            },
            user = { id = "1" },
        })

        assert.is_true(invoked)
    end)

    it("map_to errors when the group has no bare callback", function()
        local bot = Bot.new("token")
        local group = bot:bridge_group("specialcmd")
        assert.has_error(function()
            group:map_to("help")
        end)
    end)

    it("invoke_without_command registers the bare group name as a prefix command", function()
        local bot = Bot.new("token")
        local invoked = false
        bot:bridge_group("specialcmd", {
            invoke_without_command = true,
            callback = function(_ctx) invoked = true end,
        })

        bot:dispatch_message({ content = "!specialcmd", author = { id = "1" } })
        assert.is_true(invoked)
    end)

    it("does not register the bare prefix command when invoke_without_command is false", function()
        local bot = Bot.new("token")
        bot:bridge_group("specialcmd", {
            callback = function(_ctx) end,
        })

        local handled = bot:dispatch_message({ content = "!specialcmd", author = { id = "1" } })
        assert.is_false(handled)
    end)
end)
