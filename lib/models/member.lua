-- lib/models/member.lua
-- Member model for Discord API
--
-- Public Contract:
--   Member.new(data, guild) -> Member
--     Creates a new Member from API data.
--     data: table - API response data
--     guild: Guild - associated guild (optional, for convenience methods)
--
--   Member:user -> User
--     Member's user.
--
--   Member:roles -> table
--     Member's roles.
--
--   Member:joined_at -> number
--     Member join timestamp.
--
--   Member:deaf -> boolean
--     Member's deaf state (server-level).
--
--   Member:mute -> boolean
--     Member's mute state (server-level).
--
--   Member:pending -> boolean
--     True if member is pending bot verification.
--
--   Member:nick -> string or nil
--     Member's nickname (nil if none).

local class = require("core.class")

-- Member class
local Member = class("Member")

function Member.new(data, guild)
    local self = {}
    setmetatable(self, {
        __index = Member
    })

    self.guild = guild
    self.user = data.user
    self.roles = data.roles or {}
    self.joined_at = data.joined_at and tonumber(data.joined_at)
    self.deaf = data.deaf or false
    self.mute = data.mute or false
    self.pending = data.pending or false
    self.nick = data.nick or nil

    -- Additional fields
    self.joined_at_epoch = self.joined_at or nil

    return self
end

-- Get role ID from a role object
function Member:get_role_id(role)
    for _, r in ipairs(self.roles) do
        if r.id == role.id or r.name == role.name then
            return r.id
        end
    end
    return nil
end

-- Check if member has a specific role
function Member:has_role(role)
    for _, r in ipairs(self.roles) do
        if r.id == role.id or r.name == role.name then
            return true
        end
    end
    return false
end

return Member
