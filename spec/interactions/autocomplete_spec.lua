-- spec/interactions/autocomplete_spec.lua
-- Tests for M.basic_autocomplete

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local M = require("interactions.autocomplete")

describe("basic_autocomplete", function()
    it("filters a static list case-insensitively against ctx.value", function()
        local callback = M.basic_autocomplete({ "red", "orange", "yellow" })
        local result = callback({ value = "YEL" })

        assert.equals(1, #result)
        assert.equals("yellow", result[1])
    end)

    it("returns the full list when ctx.value is empty", function()
        local callback = M.basic_autocomplete({ "red", "orange", "yellow" })
        local result = callback({ value = "" })

        assert.equals(3, #result)
    end)

    it("returns the full list when ctx.value is nil", function()
        local callback = M.basic_autocomplete({ "red", "orange", "yellow" })
        local result = callback({ value = nil })

        assert.equals(3, #result)
    end)

    it("supports a callback source that receives ctx", function()
        local received_ctx = nil
        local callback = M.basic_autocomplete(function(ctx)
            received_ctx = ctx
            return { "cardinal", "ladybug" }
        end)

        local ctx = { value = "", options = { color = "red" } }
        local result = callback(ctx)

        assert.equals(ctx, received_ctx)
        assert.equals(2, #result)
    end)

    it("filters table entries by their name field", function()
        local callback = M.basic_autocomplete({
            { name = "Bulbasaur" },
            { name = "Squirtle" },
            { name = "Charmander" },
        })
        local result = callback({ value = "squ" })

        assert.equals(1, #result)
        assert.equals("Squirtle", result[1].name)
    end)

    it("caps results at 25 items", function()
        local many = {}
        for i = 1, 40 do
            many[i] = "item" .. i
        end
        local callback = M.basic_autocomplete(many)
        local result = callback({ value = "" })

        assert.equals(25, #result)
    end)
end)
