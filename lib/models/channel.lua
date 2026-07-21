-- lib/models/channel.lua
-- Channel model for Discord API
--
-- Public Contract:
--   Channel.new(data, guild, http) -> Channel
--     Creates a new Channel from API data. guild is optional, if provided
--     it is stored on self.guild for Channel:connect() and any other
--     guild-scoped behavior. http is optional, an http.client instance
--     used by Channel:send_soundboard_sound; falls back to guild.http
--     when omitted but a guild is given.
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
--
--   Channel:connect(client) -> VoiceClient
--     Connects to this channel's voice gateway, mirrors pycord's
--     voice_channel.connect(). Requires self.guild to be set (the Guild
--     this channel belongs to) and a Client instance to drive the voice
--     gateway/UDP session. Errors if self.guild is missing, or if the
--     channel is not a voice channel. Lazily requires voice.voice_client
--     so core has no hard dependency on the optional voice module.
--
--   channel:send_soundboard_sound(sound) -> nil
--     sound: a Sound (from models.sound) or a plain table with sound_id
--     and optional source_guild_id. POST /channels/{id}/send-soundboard-sound,
--     mirrors pycord's VoiceChannel.send_soundboard_sound(). Only valid for
--     voice channels.

local class = require("core.class")

-- Channel class
local Channel = class("Channel")

function Channel.new(data, guild, http)
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
    self.guild = guild
    self.http = http or (guild and guild.http)

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

-- Returns true if this channel is a voice channel. Discord's actual voice
-- channel type is 2 in the API, distinct from the placeholder mapping in
-- get_type_name above (kept as-is to avoid disturbing existing behavior).
function Channel:is_voice()
    return self.type == 2
end

-- Connects to this channel's voice gateway, mirrors pycord's
-- voice_channel.connect(). client must be a Client instance (drives
-- the underlying voice gateway/UDP session); self.guild must already be
-- set to the Guild this channel belongs to.
function Channel:connect(client)
    if not self:is_voice() then
        error("Channel:connect() called on a non-voice channel", 0)
    end

    if not self.guild then
        error("Channel:connect() requires channel.guild to be set", 0)
    end

    if not client then
        error("Channel:connect() requires a client argument", 0)
    end

    local VoiceClient = require("voice.voice_client")
    local voice_client = VoiceClient.new(client, self)
    local ok, err = voice_client:connect()
    if not ok then
        error(err, 0)
    end

    return voice_client
end

function Channel:send_soundboard_sound(sound)
    if not self:is_voice() then
        error("Channel:send_soundboard_sound() called on a non-voice channel", 0)
    end
    if not self.http then
        error("Channel has no http client attached, cannot send a soundboard sound", 0)
    end
    if not sound then
        error("Channel:send_soundboard_sound() requires a sound", 0)
    end

    local Route = require("http.route")
    local route = Route.new(self.http)

    local payload = { sound_id = sound.id or sound.sound_id }
    local source_guild_id = sound.guild_id or sound.source_guild_id
    if source_guild_id and self.guild and source_guild_id ~= self.guild.id then
        payload.source_guild_id = source_guild_id
    end

    return route:send_soundboard_sound(self.id, payload)
end

return Channel
