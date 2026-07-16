-- spec/commands/bot_spec.lua
-- Tests for bot class

-- Setup package path to find lib modules
package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

-- Clear module cache to ensure fresh load
-- Don't clear core.class - checks_spec loads it first
package.loaded["commands.bot"] = nil

local Bot = require("commands.bot")

local function table_count(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

describe("Bot", function()
    it("creates a new bot", function()
        local bot = Bot.new("token", {})

        assert.equals("token", bot.token)
        assert.same({}, bot.ratelimiter)
        assert.equals(0, table_count(bot.commands))
        assert.equals(0, table_count(bot.cogs))
        assert.equals("!", bot.prefix)
    end)

    it("registers a command", function()
        local bot = Bot.new("token")
        local handler = function(ctx, args) return "test" end
        bot:register_command("test", handler, "!")

        assert.equals(handler, bot.commands["test"])
        assert.equals("!", bot.prefixes["test"])
    end)

    it("registers an application command", function()
        local bot = Bot.new("token")
        bot:register_application_command("test", {name = "test", description = "A test command"})

        assert.equals(1, table_count(bot.application_commands))
        assert.equals("test", bot.application_commands["test"].name)
    end)

    it("unregisters a command", function()
        local bot = Bot.new("token")
        bot:register_command("test", function(ctx, args) return "test" end, "!")
        bot:unregister_command("test")

        assert.equals(nil, bot.commands["test"])
        assert.equals(nil, bot.prefixes["test"])
    end)

    it("subscribes to an event", function()
        local bot = Bot.new("token")
        local callback_called = false

        bot:on("ready", function() callback_called = true end)

        assert.equals(1, #bot.listeners["ready"])
    end)

    it("emits an event", function()
        local bot = Bot.new("token")
        local callback_called = false

        bot:on("ready", function() callback_called = true end)
        bot:emit("ready")

        assert.is_true(callback_called)
    end)

    it("adds a cog", function()
        local bot = Bot.new("token")
        local cog = { name = "test", commands = {}, listeners = {} }

        bot:add_cog(cog)

        assert.equals(1, table_count(bot.cogs))
        assert.equals(cog, bot.cogs["test"])
    end)

    it("removes a cog", function()
        local bot = Bot.new("token")
        local cog = { name = "test", commands = {}, listeners = {} }

        bot:add_cog(cog)
        bot:remove_cog(cog)

        assert.equals(nil, bot.cogs["test"])
    end)

    it("gets a command", function()
        local bot = Bot.new("token")
        local handler = function(ctx, args) return "test" end
        bot:register_command("test", handler, "!")

        local command = bot:get_command("test")

        assert.is_not_nil(command)
        assert.equals(handler, command)
        assert.equals("test", command())
    end)

    it("gets all commands", function()
        local bot = Bot.new("token")
        bot:register_command("test1", function(ctx, args) return "test1" end, "!")
        bot:register_command("test2", function(ctx, args) return "test2" end, "!")

        local commands = bot:get_commands()

        assert.equals(2, table_count(commands))
    end)

    it("emits an event with multiple listeners", function()
        local bot = Bot.new("token")
        local call_count = 0

        bot:on("test", function() call_count = call_count + 1 end)
        bot:on("test", function() call_count = call_count + 1 end)
        bot:on("test", function() call_count = call_count + 1 end)

        bot:emit("test")

        assert.equals(3, call_count)
    end)
end)