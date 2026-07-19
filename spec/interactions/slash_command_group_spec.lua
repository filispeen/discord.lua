-- spec/interactions/slash_command_group_spec.lua
-- Tests for SlashCommandGroup

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local SlashCommandGroup = require("interactions.slash_command_group")

describe("SlashCommandGroup", function()
    describe("SlashCommandGroup.new", function()
        it("sets name, description, empty checks by default", function()
            local group = SlashCommandGroup.new("math", "Math commands")
            assert.equals("math", group.name)
            assert.equals("Math commands", group.description)
            assert.same({}, group.checks)
            assert.is_nil(group.guild_ids)
        end)

        it("accepts checks and guild_ids", function()
            local check = { name = "owner", func = function() return true end }
            local group = SlashCommandGroup.new("math", "Math", {
                checks = { check },
                guild_ids = { "111" },
            })
            assert.equals(1, #group.checks)
            assert.same({ "111" }, group.guild_ids)
        end)
    end)

    describe("SlashCommandGroup:command", function()
        it("registers a direct subcommand reachable through find", function()
            local group = SlashCommandGroup.new("math", "Math commands")
            local callback = function(_ctx) end
            group:command("add", "Adds numbers", callback)

            local found = group:find({ "add" })
            assert.is_not_nil(found)
            assert.equals(callback, found.callback)
        end)

        it("subcommands inherit the group's guild_ids", function()
            local group = SlashCommandGroup.new("math", "Math", { guild_ids = { "111" } })
            local cmd = group:command("add", "Adds numbers", function() end)
            assert.same({ "111" }, cmd.guild_ids)
        end)

        it("returns nil from find for an unknown subcommand", function()
            local group = SlashCommandGroup.new("math", "Math commands")
            group:command("add", "Adds numbers", function() end)
            assert.is_nil(group:find({ "subtract" }))
        end)
    end)

    describe("SlashCommandGroup:create_subgroup", function()
        it("creates a subgroup reachable by name", function()
            local group = SlashCommandGroup.new("greetings", "Greetings")
            local subgroup = group:create_subgroup("international", "International greetings")

            assert.equals(subgroup, group.subgroups["international"])
        end)

        it("subgroup subcommands are reachable through find with a two segment path", function()
            local group = SlashCommandGroup.new("greetings", "Greetings")
            local subgroup = group:create_subgroup("international", "International greetings")
            local callback = function(_ctx) end
            subgroup:command("aloha", "Says aloha", callback)

            local found = group:find({ "international", "aloha" })
            assert.is_not_nil(found)
            assert.equals(callback, found.callback)
        end)

        it("subgroups inherit the parent group's guild_ids by default", function()
            local group = SlashCommandGroup.new("greetings", "Greetings", { guild_ids = { "111" } })
            local subgroup = group:create_subgroup("international", "International greetings")
            assert.same({ "111" }, subgroup.guild_ids)
        end)

        it("returns nil from find when the subgroup doesn't exist", function()
            local group = SlashCommandGroup.new("greetings", "Greetings")
            assert.is_nil(group:find({ "unknown", "aloha" }))
        end)
    end)

    describe("SlashCommandGroup:collect_checks", function()
        it("returns the group's own checks", function()
            local check = { name = "owner", func = function() return true end }
            local group = SlashCommandGroup.new("math", "Math", { checks = { check } })
            assert.equals(1, #group:collect_checks())
            assert.equals(check, group:collect_checks()[1])
        end)
    end)

    describe("SlashCommandGroup:to_dict", function()
        it("serializes direct subcommands as SUB_COMMAND options", function()
            local group = SlashCommandGroup.new("math", "Math commands")
            group:command("add", "Adds numbers", function() end, {
                options = { { name = "a", type = 4, required = true } },
            })

            local dict = group:to_dict()
            assert.equals("math", dict.name)
            assert.equals(1, #dict.options)
            assert.equals(1, dict.options[1].type)
            assert.equals("add", dict.options[1].name)
            assert.equals("a", dict.options[1].options[1].name)
        end)

        it("serializes subgroups as SUB_COMMAND_GROUP options containing their subcommands", function()
            local group = SlashCommandGroup.new("greetings", "Greetings")
            local subgroup = group:create_subgroup("international", "International greetings")
            subgroup:command("aloha", "Says aloha", function() end)

            local dict = group:to_dict()
            assert.equals(1, #dict.options)
            assert.equals(2, dict.options[1].type)
            assert.equals("international", dict.options[1].name)
            assert.equals(1, #dict.options[1].options)
            assert.equals("aloha", dict.options[1].options[1].name)
        end)
    end)
end)
