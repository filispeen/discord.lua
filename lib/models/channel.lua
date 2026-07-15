-- lib/models/channel.lua
-- Channel model for Discord API
--
-- Public Contract:
--   Channel.new(data) -> Channel
--     Creates a new Channel from API data.
--
--   Channel:id -> string
--     Channel's unique ID.
--
--   Channel:kind -> string
--     Channel type: "text" | "voice" | "category" | "group" | "news"
--
--   Channel:name -> string or nil
--     Channel name (nil for DM channels).
--
--   Channel:parent_id -> string or nil
--     Parent category ID (for text channels).
--
--   Channel:position -> number
--     Channel position in the list.
--
--   Channel:permission_overwrites -> table
--     Permission overwrites.
--
--   Channel:nsfw -> boolean
--     True if channel is NSFW (news channels).
--
--   Channel:rate_limit_per_user -> number
--     Rate limit per user for sending messages (in seconds).
--
--   Channel:recipient_count -> number
--     Number of recipients (for group DMs).

local class = require("core.class")

-- Channel class
local Channel = class("Channel")

function Channel.new(data)
    local self = {}
    setmetatable(self, {
        __index = Channel
    })

    self.id = data.id
    self.type = data.type
    self.name = data.name
    self.parent_id = data.parent_id
    self.position = data.position or 0
    self.permission_overwrites = data.permission_overwrites or {}
    self.nsfw = data.nsfw or false
    self.rate_limit_per_user = data.rate_limit_per_user or 0
    self.recipient_count = data.recipient_count or 0

    -- Type-specific fields
    if data.topic then
        self.topic = data.topic
    end
    if data.icon then
        self.icon = data.icon
    end
    if data.avatar then
        self.avatar = data.avatar
    end
    if data.last_message_id then
        self.last_message_id = data.last_message_id
    end
    if data.bitfield then
        self.bitfield = data.bitfield
    end

    return self
end

-- Get channel type name
function Channel:get_type_name()
    local types = {
        [1] = "text",
        [2] = "private",
        [4] = "voice",
        [5] = "group",
        [10] = "category",
        [11] = "news",
        [12] = "store",
        [13] = "news_thread",
        [14] = "public_thread",
        [15] = "private_thread",
    }
    return types[self.type] or "unknown"
end

return Channel
