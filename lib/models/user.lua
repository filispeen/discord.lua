-- lib/models/user.lua
-- User model for Discord API
--
-- Public Contract:
--   User.new(data) -> User
--     Creates a new User from API data.
--     data: table - API response data
--
--   User:id -> string
--     User's unique ID.
--
--   User:username -> string
--     User's username (can include discriminator).
--
--   User:discriminator -> string
--     User's discriminator (last 4 digits of user ID).
--
--   User:avatar -> string or nil
--     User's avatar hash (or nil if no avatar).
--
--   User:bot -> boolean
--     True if this is a bot user.
--
--   User:system -> boolean
--     True if this is a system user.

local class = require("core.class")

-- User class
local User = class("User")

function User.new(data)
    local self = {}
    setmetatable(self, {
        __index = User
    })

    self.id = data.id
    self.username = data.username
    self.discriminator = data.discriminator
    self.avatar = data.avatar
    self.bot = data.bot or false
    self.system = data.system or false
    self.mfa_enabled = data.mfa_enabled or false
    self.locale = data.locale or "en-US"
    self.verified = data.verified or false
    self.email = data.email or nil
    self.flags = data.flags or 0
    self.premium_type = data.premium_type or 0

    return self
end

-- Get display username (with discriminator if applicable)
function User:get_display_name()
    if self.bot then
        return self.username
    end
    return self.username .. "#" .. self.discriminator
end

return User
