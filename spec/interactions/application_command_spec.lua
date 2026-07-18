-- spec/interactions/application_command_spec.lua
-- Tests for ApplicationCommand construction and Discord API serialization.

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local ApplicationCommand = require("interactions.application_command")

describe("ApplicationCommand", function()
    it("serializes a command with no options", function()
        local cmd = ApplicationCommand.new("ping", "Replies with pong")
        local dict = cmd:to_dict()

        assert.equals("ping", dict.name)
        assert.equals("Replies with pong", dict.description)
        assert.equals(1, dict.type)
        assert.is_nil(dict.options)
    end)

    it("serializes options with required and choices", function()
        local cmd = ApplicationCommand.new("echo", "Echoes text", {
            { name = "text", type = 3, description = "Text to echo", required = true },
        })
        local dict = cmd:to_dict()

        assert.equals(1, #dict.options)
        assert.equals("text", dict.options[1].name)
        assert.is_true(dict.options[1].required)
    end)

    it("marks an option autocomplete true once a callback is set", function()
        local cmd = ApplicationCommand.new("search", "Search", {
            { name = "query", type = 3 },
        })
        cmd:set_autocomplete("query", function() end)

        local dict = cmd:to_dict()
        assert.is_true(dict.options[1].autocomplete)
    end)

    it("does not mark autocomplete for options without a callback", function()
        local cmd = ApplicationCommand.new("search", "Search", {
            { name = "query", type = 3 },
        })

        local dict = cmd:to_dict()
        assert.is_nil(dict.options[1].autocomplete)
    end)
end)
