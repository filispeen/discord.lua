-- spec/models/permission_spec.lua
-- Tests for permission bitmath

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

local permission = require("models.permission")

describe("Permissions", function()
    it("defines ADMINISTRATOR permission", function()
        assert.equals(268435456, permission.ADMINISTRATOR)
    end)

    it("defines VIEW_CHANNEL permission", function()
        assert.equals(1024, permission.VIEW_CHANNEL)
    end)

    it("defines SEND_MESSAGES permission", function()
        assert.equals(2048, permission.SEND_MESSAGES)
    end)

    it("has_permission works", function()
        local perms = permission.VIEW_CHANNEL | permission.SEND_MESSAGES

        assert.is_true(permission.has_permission(perms, permission.VIEW_CHANNEL))
        assert.is_true(permission.has_permission(perms, permission.SEND_MESSAGES))
        assert.is_false(permission.has_permission(perms, permission.KICK_MEMBERS))
    end)

    it("add_permission works", function()
        local perms = permission.VIEW_CHANNEL
        local new_perms = permission.add_permission(perms, permission.SEND_MESSAGES)

        assert.is_true(permission.has_permission(new_perms, permission.VIEW_CHANNEL))
        assert.is_true(permission.has_permission(new_perms, permission.SEND_MESSAGES))
    end)

    it("remove_permission works", function()
        local perms = permission.VIEW_CHANNEL | permission.SEND_MESSAGES
        local new_perms = permission.remove_permission(perms, permission.SEND_MESSAGES)

        assert.is_true(permission.has_permission(new_perms, permission.VIEW_CHANNEL))
        assert.is_false(permission.has_permission(new_perms, permission.SEND_MESSAGES))
    end)

    it("check_administrator works", function()
        assert.is_false(permission.check_administrator(0))
        assert.is_true(permission.check_administrator(permission.ADMINISTRATOR))
        assert.is_true(permission.check_administrator(permission.ADMINISTRATOR | permission.VIEW_CHANNEL))
    end)

    it("can_send_messages works", function()
        assert.is_true(permission.can_send_messages(permission.SEND_MESSAGES))
        assert.is_false(permission.can_send_messages(0))
    end)

    it("can_manage_guild works", function()
        assert.is_true(permission.can_manage_guild(permission.MANAGE_GUILD))
        assert.is_false(permission.can_manage_guild(0))
    end)

    it("can_ban_members works", function()
        assert.is_true(permission.can_ban_members(permission.BANN_MEMBERS))
        assert.is_false(permission.can_ban_members(0))
    end)
end)
