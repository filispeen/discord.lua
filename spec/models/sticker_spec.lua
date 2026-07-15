-- spec/models/sticker_spec.lua
-- Tests for sticker model

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

local Sticker = require("models.sticker")

describe("Sticker", function()
    it("creates a new sticker", function()
        local sticker = Sticker.new({
            id = "123",
            name = "Test Sticker",
            sort_value = 1,
            description = "A test sticker",
            pack_id = "456",
            type = 1,
            user = {
                id = "789",
                username = "User",
                discriminator = "0001",
                avatar = "abc123",
            },
        })

        assert.equals("123", sticker.id)
        assert.equals("Test Sticker", sticker.name)
        assert.equals(1, sticker.sort_value)
        assert.equals("A test sticker", sticker.description)
        assert.equals("456", sticker.pack_id)
        assert.equals(1, sticker.type)
        assert.equals("789", sticker.user.id)
    end)

    it("is_premium returns true for type 2", function()
        local sticker = Sticker.new({
            id = "123",
            name = "Premium Sticker",
            type = 2,
        })

        assert.is_true(sticker:is_premium())
    end)

    it("is_premium returns false for type 1", function()
        local sticker = Sticker.new({
            id = "123",
            name = "Standard Sticker",
            type = 1,
        })

        assert.is_false(sticker:is_premium())
    end)

    it("get_url returns sticker URL", function()
        local sticker = Sticker.new({
            id = "123",
            name = "Test",
        })

        assert.equals("https://cdn.discordapp.com/stickers/123.png", sticker:get_url())
    end)

    it("get_pack_url returns pack URL", function()
        local sticker = Sticker.new({
            id = "123",
            name = "Test",
            pack_id = "456",
        })

        assert.equals("https://cdn.discordapp.com/sticker-packs/456.png", sticker:get_pack_url())
    end)
end)
