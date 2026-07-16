-- spec/commands/command_spec.lua
-- Tests for command class

-- Setup package path to find lib modules
package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local M = require("commands.command")

describe("Command", function()
    it("creates a new command", function()
        local command = M.new("test", "A test command", "!test arg1 arg2")

        assert.equals("test", command.name)
        assert.equals("A test command", command.description)
        assert.equals("!test arg1 arg2", command.usage)
        assert.equals("", command.example)
        assert.equals(0, #command.aliases)
        assert.equals(0, #command.checks)
    end)

    it("adds an alias", function()
        local command = M.new("test")
        command:add_alias("t")
        command:add_alias("alias1")

        assert.equals(2, #command.aliases)
        assert.equals("t", command.aliases[1])
        assert.equals("alias1", command.aliases[2])
    end)

    it("adds a check", function()
        local command = M.new("test")
        command:add_check(function(ctx) return true end)
        command:add_check(function(ctx) return false end)

        assert.equals(2, #command.checks)
    end)

    it("sets an example", function()
        local command = M.new("test")
        command.example = "!test arg1"

        assert.equals("!test arg1", command.example)
    end)

    it("gets all command names including aliases", function()
        local command = M.new("test", "Test command", "!test")
        command:add_alias("t")
        command:add_alias("alias")

        local names = command:get_all_names()

        assert.equals(3, #names)
        assert.equals("test", names[1])
        assert.equals("t", names[2])
        assert.equals("alias", names[3])
    end)

    it("returns empty names for command without aliases", function()
        local command = M.new("test")

        local names = command:get_all_names()

        assert.equals(1, #names)
        assert.equals("test", names[1])
    end)
end)
