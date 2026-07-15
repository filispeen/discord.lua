-- spec/models/invite_spec.lua
-- Tests for invite model

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

local Invite = require("models.invite")

describe("Invite", function()
    it("creates a new invite", function()
        local invite = Invite.new({
            code = "abc123",
            guild = {
                id = "123",
                name = "Test Guild",
            },
            channel = {
                id = "456",
                name = "Test Channel",
            },
            inviter = {
                id = "789",
                username = "Inviter",
                discriminator = "0001",
            },
            max_age = 3600,
            max_uses = 10,
            temporary = true,
            created_at = "1234567890",
        })

        assert.equals("abc123", invite.code)
        assert.equals("123", invite.guild.id)
        assert.equals("456", invite.channel.id)
        assert.equals("789", invite.inviter.id)
        assert.equals(3600, invite.max_age)
        assert.equals(10, invite.max_uses)
        assert.is_true(invite.temporary)
        assert.equals("1234567890", invite.created_at)
    end)

    it("is_expired returns true after max_age", function()
        local now = os.time()
        local invite = Invite.new({
            code = "abc123",
            max_age = 1000, -- 1 second
            created_at = os.date("!%Y-%m-%dT%H:%M:%SZ", now - 1000), -- 1 second ago
        })

        assert.is_true(invite:is_expired())
    end)

    it("is_expired returns false before max_age", function()
        local now = os.time()
        local invite = Invite.new({
            code = "abc123",
            max_age = 1000,
            created_at = os.date("!%Y-%m-%dT%H:%M:%SZ", now + 1000000), -- 1 second in the future
        })

        assert.is_false(invite:is_expired())
    end)

    it("is_expired returns false when no max_age", function()
        local invite = Invite.new({
            code = "abc123",
            max_age = nil,
        })

        assert.is_false(invite:is_expired())
    end)

    it("is_full returns true when uses >= max_uses", function()
        local invite = Invite.new({
            code = "abc123",
            max_uses = 10,
            uses = 10,
        })

        assert.is_true(invite:is_full())
    end)

    it("is_full returns false when uses < max_uses", function()
        local invite = Invite.new({
            code = "abc123",
            max_uses = 10,
            uses = 5,
        })

        assert.is_false(invite:is_full())
    end)

    it("is_full returns false when no max_uses", function()
        local invite = Invite.new({
            code = "abc123",
            max_uses = nil,
            uses = 5,
        })

        assert.is_false(invite:is_full())
    end)
end)
