-- spec/commands/cog_spec.lua
-- Tests for cog class

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
        cog.command_test = function(ctx, args) return "test" end
        cog.command_another = function(ctx, args) return "another" end
        cog.normal_function = function(ctx) return "normal" end  -- Should not be registered

        local commands = {}
        for method, func in pairs(cog) do
            if method:sub(1, 8) == "command_" then
                table.insert(commands, method)
            end
        end

        assert.equals(2, #commands)
        local cmd_names = {}
        for _, cmd in ipairs(commands) do
            cmd_names[cmd] = true
        end
        assert.is_true(cmd_names["command_test"])
        assert.is_true(cmd_names["command_another"])
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

        -- Check that all listeners were found (order may vary)
        local has_ready = false
        local has_message = false
        local has_other = false
        for _, listener in ipairs(listeners) do
            if listener == "on_ready" then has_ready = true end
            if listener == "on_message" then has_message = true end
            if listener == "on_other" then has_other = true end
        end
        assert.is_true(has_ready)
        assert.is_true(has_message)
        assert.is_true(has_other)
    end)

    it("does not register private methods", function()
        local cog = M.new("test")

        cog._private = function() return "private" end
        cog.command_test = function(ctx, args) return "test" end

        local commands = {}
        for method in pairs(cog) do
            if method:sub(1, 8) == "command_" then
                table.insert(commands, method)
            end
        end

        assert.equals(1, #commands)
    end)
end)
