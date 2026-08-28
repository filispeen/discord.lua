-- lib/models/emoji.lua
-- Emoji model for Discord API
--
-- Public Contract:
--   Emoji.new(data) -> Emoji
--     Creates a new Emoji from API data.
--
--   Emoji:id -> string or nil
--     Emoji's unique ID (nil for pre-defined emojis).
--
--   Emoji:name -> string
--     Emoji name.
--
--   Emoji:role_ids -> table
--     Role IDs required to use emoji.
--
--   Emoji:managed -> boolean
--     True if emoji is managed by an external service.
--
--   Emoji:require_colons -> boolean
--     True if emoji must be prefixed with colons.
--
--   Emoji:animated -> boolean
--     True if emoji is animated.

local class = require("../core/class")

-- Emoji class
local Emoji = class("Emoji")

function Emoji.new(data, guild, http)
    local self = {}
    setmetatable(self, {
        __index = Emoji
    })

    self.id = data.id
    self.name = data.name
    self.roles = data.roles or {}
    self.managed = data.managed or false
    self.require_colons = data.require_colons or false
    self.animated = data.animated or false
    self.guild = guild
    self.guild_id = data.guild_id or (guild and guild.id)
    self.http = http or (guild and guild.http)

    return self
end

-- Get emoji URL
function Emoji:get_url(size)
    local size_str = size or "480"
    return "https://cdn.discordapp.com/emojis/" .. self.id .. ".png?size=" .. size_str
end

function Emoji:edit(opts)
    opts = opts or {}
    if not self.http or not self.guild_id then error("Emoji has no guild http context, cannot edit", 0) end
    local Route = require("../http/route")
    local data = Route.new(self.http):edit_guild_emoji(self.guild_id, self.id, { name = opts.name, roles = opts.roles }, opts.reason)
    self.name = data.name or self.name
    self.roles = data.roles or self.roles
    return self
end

function Emoji:delete(reason)
    if not self.http or not self.guild_id then error("Emoji has no guild http context, cannot delete", 0) end
    local Route = require("../http/route")
    return Route.new(self.http):delete_guild_emoji(self.guild_id, self.id, reason)
end

return Emoji
