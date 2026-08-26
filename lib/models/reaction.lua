-- lib/models/reaction.lua
-- Reaction model for Discord API
--
-- Public Contract:
--   Reaction.new(data) -> Reaction
--     Creates a new Reaction from a raw API reaction payload
--     ({emoji, count, count_details, me, me_burst, burst_colors}).
--
--   Reaction.key(emoji) -> string or nil
--     Stable string key for a raw emoji payload ({id, name}): "name"
--     for a unicode emoji, "name:id" for a custom emoji. Used to match
--     the same emoji across separate gateway reaction payloads, since
--     Discord does not give reactions a stable id of their own.
--
--   Reaction:emoji -> table
--     Raw emoji payload ({id, name, animated}).
--
--   Reaction:emoji_key -> string
--     This reaction's own emoji key, see Reaction.key above.
--
--   Reaction:count -> number
--     Combined total of normal and super reactions for this emoji.
--
--   Reaction:count_normal -> number
--     Normal (non-burst) reaction count, from count_details.normal.
--
--   Reaction:count_burst -> number
--     Super/burst reaction count, from count_details.burst.
--
--   Reaction:me -> boolean
--     True if the bot has reacted with this emoji normally.
--
--   Reaction:me_burst -> boolean
--     True if the bot has reacted with this emoji as a super reaction.

local class = require("../core/class")

local Reaction = class("Reaction")

local function emoji_key(emoji)
    if not emoji then
        return nil
    end
    if emoji.id then
        return (emoji.name or "") .. ":" .. emoji.id
    end
    return emoji.name
end

Reaction.key = emoji_key

function Reaction.new(data)
    local self = {}
    setmetatable(self, {
        __index = Reaction
    })

    self.emoji = data.emoji or {}
    self.emoji_key = emoji_key(self.emoji)
    self.count = data.count or 0
    local count_details = data.count_details or {}
    self.count_normal = count_details.normal or 0
    self.count_burst = count_details.burst or 0
    self.me = data.me or false
    self.me_burst = data.me_burst or false
    self.burst_colors = data.burst_colors or {}

    return self
end

return Reaction
