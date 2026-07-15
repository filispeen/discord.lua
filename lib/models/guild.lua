-- lib/models/guild.lua
-- Guild model for Discord API
--
-- Public Contract:
--   Guild.new(data) -> Guild
--     Creates a new Guild from API data.
--
--   Guild:id -> string
--     Guild's unique ID.
--
--   Guild:name -> string
--     Guild name.
--
--   Guild:icon -> string or nil
--     Guild icon hash (or nil if no icon).
--
--   Guild:owner_id -> string
--     Guild owner's user ID.
--
--   Guild:roles -> table
--     Guild roles.
--
--   Guild:emojis -> table
--     Guild emojis.
--
--   Guild:channels -> table
--     Guild channels.
--
--   Guild:member_count -> number
--     Number of guild members.
--
--   Guild:features -> table
--     Guild features.
--
--   Guild:verification_level -> number
--     Guild verification level.
--
--   Guild:vanity_url_code -> string or nil
--     Vanity URL code.
--
--   Guild:premium_subscription_level -> number
--     Premium subscription level.
--
--   Guild:nsfw -> boolean
--     True if guild is NSFW.

local class = require("core.class")

-- Guild class
local Guild = class("Guild")

function Guild.new(data)
    local self = {}
    setmetatable(self, {
        __index = Guild
    })

    self.id = data.id
    self.name = data.name
    self.icon = data.icon
    self.owner_id = data.owner_id
    self.roles = data.roles or {}
    self.emojis = data.emojis or {}
    self.channels = data.channels or {}
    self.member_count = data.member_count or 0
    self.features = data.features or {}
    self.verification_level = data.verification_level or 1
    self.vanity_url_code = data.vanity_url_code
    self.premium_subscription_level = data.premium_subscription_level or 0
    self.nsfw = data.nsfw or false

    -- Additional fields
    self.afk_channel_id = data.afk_channel_id or nil
    self.afk_timeout = data.afk_timeout or 300
    self.region = data.region or "us-west"
    self.joined_at = data.joined_at or nil
    self.large = data.large or false
    self.unavailable = data.unavailable or false
    self.splash = data.splash or nil
    self.discovery_splash = data.discovery_splash or nil
    self.description = data.description or nil
    self.bans = data.bans or {}
    self.threads = data.threads or {}
    self.webhooks = data.webhooks or {}
    self.stickers = data.stickers or {}
    self.explicit_content_filter = data.explicit_content_filter or 0
    self.mfa_level = data.mfa_level or 1

    return self
end

return Guild
