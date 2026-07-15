-- lib/models/role.lua
-- Role model for Discord API
--
-- Public Contract:
--   Role.new(data) -> Role
--     Creates a new Role from API data.
--
--   Role:id -> string
--     Role's unique ID.
--
--   Role:name -> string
--     Role name.
--
--   Role:color -> number
--     Role color (0 = default).
--
--   Role:hoist -> boolean
--     True if role should be displayed separately in user list.
--
--   Role:mentionable -> boolean
--     True if role can be mentioned.
--
--   Role:permissions -> number
--     Role's permissions bitmask.
--
--   Role:position -> number
--     Role's sort position.
--
--   Role:managed -> boolean
--     True if role is managed by an integration.
--
--   Role:icon -> string or nil
--     Role's custom emoji icon.
--
--   Role:emoji -> table or nil
--     Role's custom emoji.

local class = require("core.class")

-- Role class
local Role = class("Role")

function Role.new(data)
    local self = {}
    setmetatable(self, {
        __index = Role
    })

    self.id = data.id
    self.name = data.name
    self.color = data.color or 0
    self.hoist = data.hoist or false
    self.mentionable = data.mentionable or false
    self.permissions = data.permissions or 0

    -- Additional fields
    self.position = data.position or 0
    self.managed = data.managed or false
    self.icon = data.icon or nil
    self.emoji = data.emoji or nil

    return self
end

-- Get role color as RGB string
function Role:get_rgb()
    local r = (self.color >> 16) % 256
    local g = (self.color >> 8) % 256
    local b = self.color % 256
    return string.format("#%02x%02x%02x", r, g, b)
end

return Role
