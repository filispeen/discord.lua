-- spec/commands/group_spec.lua
-- Tests for group class

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local M = require("commands.group")

describe("Group", function()
    it("creates a new group", function()
        local group = M.new("test", "A test group")

        assert.equals("test", group.name)
        assert.equals("A test group", group.description)
        assert.equals("", group.usage)
        assert.equals("", group.example)
        assert.equals(0, #group.aliases)
        assert.equals(0, #group.subcommands)
    end)

    it("adds an alias", function()
        local group = M.new("test")
        group:add_alias("t")
        group:add_alias("alias1")

        assert.equals(2, #group.aliases)
        assert.equals("t", group.aliases[1])
        assert.equals("alias1", group.aliases[2])
    end)

    it("adds a subcommand", function()
        local group = M.new("test")
        group:add_subcommand("sub1", "First subcommand")
        group:add_subcommand("sub2", "Second subcommand")

        assert.equals(2, #group.subcommands)
        assert.equals("sub1", group.subcommands[1].name)
        assert.equals("First subcommand", group.subcommands[1].description)
        assert.equals("sub2", group.subcommands[2].name)
    end)

    it("gets full command name", function()
        local group = M.new("test")

        assert.equals("test", group:get_full_name())
        assert.equals("test sub1", group:get_full_name("sub1"))
        assert.equals("test sub2", group:get_full_name("sub2"))
    end)

    it("handles empty subcommand name", function()
        local group = M.new("test")

        assert.equals("test", group:get_full_name())
    end)
end)
