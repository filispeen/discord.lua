-- spec/models/emoji_spec.lua
-- Tests for emoji model

-- Setup package path to find lib modules
package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

-- Mock luv before loading gateway modules
package.loaded["luv"] = {
    timer = {
        new = function()
            return {
                start = function() end,
                stop = function() end,
            }
        end
    },
    now = function() return 0 end
}

local Emoji = require("models.emoji")

describe("Emoji", function()
    it("creates a new emoji", function()
        local emoji = Emoji.new({
            id = "123",
            name = "test",
            roles = {"1", "2", "3"},
            managed = true,
            require_colons = true,
            animated = true,
        })

        assert.equals("123", emoji.id)
        assert.equals("test", emoji.name)
        assert.equals(3, #emoji.roles)
        assert.is_true(emoji.managed)
        assert.is_true(emoji.require_colons)
        assert.is_true(emoji.animated)
    end)

    it("get_url returns emoji URL", function()
        local emoji = Emoji.new({
            id = "123",
            name = "test",
        })

        assert.equals("https://cdn.discordapp.com/emojis/123.png?size=480", emoji:get_url("480"))
    end)

    it("get_url with nil size", function()
        local emoji = Emoji.new({
            id = "123",
            name = "test",
        })

        assert.equals("https://cdn.discordapp.com/emojis/123.png?size=480", emoji:get_url())
    end)
end)
