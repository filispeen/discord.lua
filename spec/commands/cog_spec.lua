-- spec/commands/cog_spec.lua
-- Tests for cog class

-- Setup package path to find lib modules
package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local M = require("commands.cog")

describe("Cog", function()
    it("creates a new cog", function()
        local cog = M.new("test")

        assert.equals("test", cog.name)
        assert.equals(0, #cog.commands)
        assert.equals(0, #cog.listeners)
    end)

    it("discovers command methods", function()
        local cog = M.new("test")

        -- Simulate registering commands
        cog.test_command = function(ctx, args) return "test" end
        cog.another_command = function(ctx, args) return "another" end
        cog.normal_function = function(ctx) return "normal" end  -- Should not be registered

        local commands = {}
        for method, func in pairs(cog) do
            if method:sub(1, 8) == "command_" then
                table.insert(commands, method)
            end
        end

        assert.equals(2, #commands)
        assert.equals("test_command", commands[1])
        assert.equals("another_command", commands[2])
    end)

    it("discovers listener methods", function()
        local cog = M.new("test")

        cog.on_ready = function() return "ready" end
        cog.on_message = function(msg) return msg end
        cog.on_other = function() return "other" end

        local listeners = {}
        for method, func in pairs(cog) do
            if method:sub(1, 3) == "on_" then
                table.insert(listeners, method)
            end
        end

        assert.equals(3, #listeners)
        assert.equals("on_ready", listeners[1])
        assert.equals("on_message", listeners[2])
        assert.equals("on_other", listeners[3])
    end)

    it("does not register private methods", function()
        local cog = M.new("test")

        cog._private = function() return "private" end
        cog.test_command = function(ctx, args) return "test" end

        local commands = {}
        for method in pairs(cog) do
            if method:sub(1, 8) == "command_" then
                table.insert(commands, method)
            end
        end

        assert.equals(1, #commands)
    end)
end)
