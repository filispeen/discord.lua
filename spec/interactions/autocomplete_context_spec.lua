-- spec/interactions/autocomplete_context_spec.lua
-- Tests for AutocompleteContext

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local AutocompleteContext = require("interactions.autocomplete_context")

describe("AutocompleteContext", function()
    it("sets value from the focused option", function()
        local interaction = {
            data = {
                name = "search",
                options = { { name = "query", value = "abc", focused = true } },
            },
        }
        local ctx = AutocompleteContext.new(interaction, nil, "query")
        assert.equals("abc", ctx.value)
    end)

    it("exposes every option's value through ctx.options", function()
        local interaction = {
            data = {
                name = "ac_example",
                options = {
                    { name = "color", value = "red" },
                    { name = "animal", value = "cat", focused = true },
                },
            },
        }
        local ctx = AutocompleteContext.new(interaction, nil, "animal")
        assert.equals("red", ctx.options["color"])
        assert.equals("cat", ctx.options["animal"])
        assert.equals("cat", ctx.value)
    end)

    it("flattens options nested under a subcommand", function()
        local interaction = {
            data = {
                name = "group",
                options = {
                    {
                        name = "sub",
                        type = 1,
                        options = {
                            { name = "query", value = "xyz", focused = true },
                        },
                    },
                },
            },
        }
        local ctx = AutocompleteContext.new(interaction, nil, "query")
        assert.equals("xyz", ctx.value)
        assert.equals("xyz", ctx.options["query"])
    end)

    it("stores the client as ctx.bot and the raw interaction", function()
        local client = { id = "bot1" }
        local interaction = { data = { name = "search", options = {} } }
        local ctx = AutocompleteContext.new(interaction, client, "query")
        assert.equals(client, ctx.bot)
        assert.equals(interaction, ctx.interaction)
    end)

    it("stores the command reference when given", function()
        local command = { name = "search" }
        local interaction = { data = { name = "search", options = {} } }
        local ctx = AutocompleteContext.new(interaction, nil, "query", command)
        assert.equals(command, ctx.command)
    end)

    it("value is nil when the focused option is not present", function()
        local interaction = { data = { name = "search", options = {} } }
        local ctx = AutocompleteContext.new(interaction, nil, "query")
        assert.is_nil(ctx.value)
    end)
end)
