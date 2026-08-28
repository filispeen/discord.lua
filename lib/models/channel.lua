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
--
--   channel:create_invite(opts) -> Invite
--     opts.max_age / opts.max_uses / opts.temporary / opts.unique: standard
--     invite options, all optional.
--     opts.target_users_file: string or nil - CSV content listing target
--     user ids, restricts the invite to only those users. Mirrors pycord's
--     create_invite(target_users_file=...), see models.invite for the
--     JSON-vs-multipart caveat.
--     POST /channels/{id}/invites.
--
--   channel:create_thread(opts) -> Thread
--     opts.name (required), opts.message_id (optional - starts the
--     thread from that message via POST .../messages/{id}/threads,
--     always a public thread), opts.type (only used without a message,
--     defaults to 15 = private_thread per this project's type mapping),
--     opts.auto_archive_duration, opts.slowmode_delay, opts.invitable,
--     opts.reason. Mirrors pycord's TextChannel.create_thread(), picks
--     between start_thread_with_message/start_thread_without_message.
--
--   channel:create_instance(opts) -> StageInstance
--     opts.topic (required), opts.privacy_level (optional),
--     opts.send_notification (optional boolean, maps to
--     send_start_notification, default false), opts.reason. POST
--     /stage-instances, mirrors pycord's StageChannel.create_instance().
--     No channel-type check is enforced (same as create_thread above),
--     intended for stage channels.
--
--   channel:fetch_instance() -> StageInstance
--     GET /stage-instances/{id}, mirrors pycord's
--     StageChannel.fetch_instance().

local class = require("../core/class")

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

    local VoiceClient = require("../voice/voice_client")
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

    local Route = require("../http/route")
    local route = Route.new(self.http)

    local payload = { sound_id = sound.id or sound.sound_id }
    local source_guild_id = sound.guild_id or sound.source_guild_id
    if source_guild_id and self.guild and source_guild_id ~= self.guild.id then
        payload.source_guild_id = source_guild_id
    end

    return route:send_soundboard_sound(self.id, payload)
end

function Channel:create_invite(opts)
    opts = opts or {}
    if not self.http then
        error("Channel has no http client attached, cannot create an invite", 0)
    end

    local Route = require("../http/route")
    local Invite = require("./invite")
    local route = Route.new(self.http)

    local payload = {
        max_age = opts.max_age,
        max_uses = opts.max_uses,
        temporary = opts.temporary or false,
        unique = opts.unique or false,
    }
    if opts.target_users_file then
        payload.target_users_file = opts.target_users_file
    end

    local created = route:create_channel_invite(self.id, payload, opts.reason)
    return Invite.new(created, self.http)
end

function Channel:create_thread(opts)
    opts = opts or {}
    if not self.http then
        error("Channel has no http client attached, cannot create_thread", 0)
    end
    if not opts.name then
        error("Channel:create_thread() requires opts.name", 0)
    end

    local Thread = require("./thread")
    local endpoint
    local payload = {
        name = opts.name,
        auto_archive_duration = opts.auto_archive_duration or 1440,
        rate_limit_per_user = opts.slowmode_delay or 0,
    }

    if opts.message_id then
        endpoint = "/channels/" .. self.id .. "/messages/" .. opts.message_id .. "/threads"
    else
        endpoint = "/channels/" .. self.id .. "/threads"
        payload.type = opts.type or 15
        if opts.invitable ~= nil then
            payload.invitable = opts.invitable
        end
    end

    local created = self.http:post(endpoint, payload)
    return Thread.new(created, self.guild, self.http)
end

function Channel:fetch_archived_threads(opts)
    opts = opts or {}
    if not self.http then
        error("Channel has no http client attached, cannot fetch archived threads", 0)
    end
    local params = {}
    if opts.before then
        params.before = opts.before
    end
    if opts.limit then
        params.limit = opts.limit
    end
    local Route = require("../http/route")
    local Thread = require("./thread")
    local data = Route.new(self.http):get_archived_threads(self.id, opts.kind, params)
    local threads = {}
    for index, thread_data in ipairs(data.threads or {}) do
        threads[index] = Thread.new(thread_data, self.guild, self.http)
    end
    data.threads = threads
    return data
end

function Channel:create_webhook(opts)
    opts = opts or {}
    if not self.http then
        error("Channel has no http client attached, cannot create webhook", 0)
    end
    if not opts.name then
        error("Channel:create_webhook requires opts.name", 0)
    end
    local Route = require("../http/route")
    local Webhook = require("./webhook")
    local data = Route.new(self.http):create_webhook(self.id, { name = opts.name, avatar = opts.avatar }, opts.reason)
    return Webhook.new(data, self.http)
end

function Channel:fetch_webhooks()
    if not self.http then
        error("Channel has no http client attached, cannot fetch webhooks", 0)
    end
    local Route = require("../http/route")
    local Webhook = require("./webhook")
    local data = Route.new(self.http):get_channel_webhooks(self.id)
    local webhooks = {}
    for index, webhook_data in ipairs(data or {}) do
        webhooks[index] = Webhook.new(webhook_data, self.http)
    end
    return webhooks
end

function Channel:follow(webhook_channel_id, reason)
    if not self.http then
        error("Channel has no http client attached, cannot follow", 0)
    end
    local Route = require("../http/route")
    local Webhook = require("./webhook")
    local data = Route.new(self.http):follow_channel(self.id, webhook_channel_id, reason)
    return Webhook.new({ id = data.webhook_id }, self.http)
end

function Channel:create_instance(opts)
    opts = opts or {}
    if not self.http then
        error("Channel has no http client attached, cannot create_instance", 0)
    end
    if not opts.topic then
        error("Channel:create_instance() requires opts.topic", 0)
    end

    local Route = require("../http/route")
    local StageInstance = require("./stage_instance")
    local route = Route.new(self.http)

    local payload = {
        channel_id = self.id,
        topic = opts.topic,
        send_start_notification = opts.send_notification or false,
    }
    if opts.privacy_level ~= nil then
        payload.privacy_level = opts.privacy_level
    end

    local created = route:create_stage_instance(payload, opts.reason)
    return StageInstance.new(created, self.guild, self.http)
end

function Channel:fetch_instance()
    if not self.http then
        error("Channel has no http client attached, cannot fetch_instance", 0)
    end

    local Route = require("../http/route")
    local StageInstance = require("./stage_instance")
    local route = Route.new(self.http)

    local data = route:get_stage_instance(self.id)
    return StageInstance.new(data, self.guild, self.http)
end

return Channel
