-- spec/models/role_spec.lua
-- Tests for role model

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

local Role = require("models.role")
local permission = require("models.permission")

describe("Role", function()
    it("creates a new role", function()
        local role = Role.new({
            id = "123",
            name = "Test Role",
            color = 0xFF0000,
            hoist = true,
            mentionable = true,
            permissions = permission.VIEW_CHANNEL,
            position = 1,
            managed = true,
        })

        assert.equals("123", role.id)
        assert.equals("Test Role", role.name)
        assert.equals(0xFF0000, role.color)
        assert.is_true(role.hoist)
        assert.is_true(role.mentionable)
        assert.equals(permission.VIEW_CHANNEL, role.permissions)
        assert.equals(1, role.position)
        assert.is_true(role.managed)
    end)

    it("defaults missing fields", function()
        local role = Role.new({
            id = "123",
            name = "Test",
        })

        assert.equals(0, role.color)
        assert.is_false(role.hoist)
        assert.is_false(role.mentionable)
        assert.equals(0, role.permissions)
        assert.equals(0, role.position)
        assert.is_false(role.managed)
    end)

    it("get_rgb converts color", function()
        local role = Role.new({
            id = "123",
            name = "Test",
            color = 0xFF0000, -- Red
        })

        assert.equals("#ff0000", role:get_rgb())
    end)
end)
