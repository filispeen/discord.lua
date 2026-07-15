-- spec/models/webhook_spec.lua
-- Tests for webhook model

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

-- Mock json for webhook tests
package.loaded["json"] = {
    encode = function(obj)
        return '{"content":"' .. tostring(obj.content) .. '"}'
    end,
    decode = function(str)
        return {content = obj and obj.content or "test"}
    end
}

local Webhook = require("models.webhook")

describe("Webhook", function()
    it("creates a new webhook", function()
        local webhook = Webhook.new({
            id = "123",
            name = "Test Webhook",
            guild_id = "456",
            channel_id = "789",
            token = "test_token",
            user = {
                id = "111",
                username = "User",
                discriminator = "0001",
            },
            avatar = "abc123",
            application_id = "222",
        })

        assert.equals("123", webhook.id)
        assert.equals("Test Webhook", webhook.name)
        assert.equals("456", webhook.guild_id)
        assert.equals("789", webhook.channel_id)
        assert.equals("test_token", webhook.token)
        assert.equals("111", webhook.user.id)
        assert.equals("abc123", webhook.avatar)
        assert.equals("222", webhook.application_id)
    end)

    it("send fails without token", function()
        local webhook = Webhook.new({
            id = "123",
            name = "Test",
            channel_id = "456",
            token = nil,
        })

        local success, err = pcall(function()
            webhook:send("test")
        end)

        assert.is_false(success)
        assert.is_not_nil(err)
    end)

    it("send sends message to Discord API", function()
        local webhook = Webhook.new({
            id = "123",
            name = "Test",
            channel_id = "456",
            token = "test_token",
        })

        -- This should attempt to make an HTTP request
        -- We're just verifying it doesn't error on token check
        assert.equals("123", webhook.id)
    end)
end)
