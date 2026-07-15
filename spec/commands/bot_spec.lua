-- spec/commands/bot_spec.lua
-- Tests for bot class

-- Setup package path to find lib modules
package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

-- Mock the required modules
package.loaded["core.class"] = {
    class = function(name, parent)
        local cls = { _name = name }
        setmetatable(cls, {
            __index = parent or cls,
            __call = function(cls, ...)
                if cls.new then return cls.new(...) end
                return {}
            end
        })
        return cls
    end
}

local M = require("commands.bot")

describe("Bot", function()
    it("creates a new bot", function()
        local bot = M.new("token", {})

        assert.equals("token", bot.token)
        assert.equals(nil, bot.ratelimiter)
        assert.equals(0, #bot.commands)
        assert.equals(0, #bot.cogs)
        assert.equals("", bot.prefix)
    end)

    it("registers a command", function()
        local bot = M.new("token")
        bot:register_command("test", function(ctx, args) return "test" end, "!")

        assert.equals(1, #bot.commands)
        assert.equals("test", bot.commands["test"])
    end)

    it("registers a cog", function()
        local bot = M.new("token")
        local cog = {
            test_command = function(ctx, args) return "test" end,
            on_ready = function() return "ready" end
        }
        bot:add_cog(cog)

        assert.equals(1, #bot.cogs)
    end)

    it("gets a command", function()
        local bot = M.new("token")
        bot:register_command("test", function(ctx, args) return "test" end, "!")

        local command = bot:get_command("test")
        assert.is_not_nil(command)
        assert.equals("test", command.name)
    end)

    it("gets all commands", function()
        local bot = M.new("token")
        bot:register_command("test1", function(ctx, args) return "test1" end, "!")
        bot:register_command("test2", function(ctx, args) return "test2" end, "!")

        local commands = bot:get_commands()
        assert.equals(2, #commands)
    end)

    it("emits an event", function()
        local bot = M.new("token")
        local events = {}

        bot:on("test_event", function(...)
            table.insert(events, ...)
        end)

        bot:emit("test_event", "arg1", "arg2")

        assert.equals(2, #events)
        assert.equals("arg1", events[1])
        assert.equals("arg2", events[2])
    end)

    it("handles multiple listeners for same event", function()
        local bot = M.new("token")
        local events = {}

        bot:on("test_event", function(...)
            table.insert(events, "listener1")
        end)

        bot:on("test_event", function(...)
            table.insert(events, "listener2")
        end)

        bot:emit("test_event")

        assert.equals(2, #events)
        assert.equals("listener1", events[1])
        assert.equals("listener2", events[2])
    end)
end)
