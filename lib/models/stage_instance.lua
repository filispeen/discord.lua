-- lib/models/stage_instance.lua
-- StageInstance model for Discord API
--
-- Public Contract:
--   StageInstance.new(data, guild?, http?) -> StageInstance
--     Creates a new StageInstance from a raw API payload. guild is
--     optional (stored on self.guild, used for guild_id fallback). http
--     is optional, falls back to guild.http.
--
--   StageInstance:id / :guild_id / :channel_id -> string
--   StageInstance:topic -> string
--   StageInstance:privacy_level -> number (StagePrivacyLevel: 1 public
--     (deprecated by Discord), 2 guild_only). Raw int, this project
--     does not define an enum table for it, same style as e.g.
--     ScheduledEvent.status.
--   StageInstance:discoverable_disabled -> boolean
--   StageInstance:scheduled_event_id -> string or nil
--     Raw `guild_scheduled_event_id` from the payload. pycord resolves
--     this into a full ScheduledEvent via `guild.get_scheduled_event`
--     (guild.py's internal `_scheduled_events` cache) -- Guild here
--     holds no such cache (see NOT_MADE.md pt.6), so it stays a raw id.
--     Callers that already have the event id can pair it with
--     `Guild:fetch_scheduled_event(event_id)` themselves.
--
--   StageInstance:edit(opts) -> StageInstance (self)
--     PATCH /stage-instances/{channel_id}. opts.topic / opts.privacy_level
--     / opts.reason, all optional. Updates self in place from the
--     response (the endpoint itself returns no body per Discord's docs,
--     so self is patched locally from opts instead, mirrors pycord's
--     edit() which also has no return value).
--
--   StageInstance:delete(reason?) -> table
--     DELETE /stage-instances/{channel_id}.
--
--   channel:create_instance(opts) -> StageInstance
--     opts.topic (required), opts.privacy_level (optional), opts.send_notification
--     (optional boolean, maps to send_start_notification, default false),
--     opts.reason. POST /stage-instances, mirrors pycord's
--     StageChannel.create_instance().
--
--   channel:fetch_instance() -> StageInstance
--     GET /stage-instances/{id}, mirrors pycord's
--     StageChannel.fetch_instance().

local class = require("../core/class")

local StageInstance = class("StageInstance")

local function apply(self, data)
    data = data or {}
    self.id = data.id or self.id
    self.channel_id = data.channel_id or self.channel_id
    self.guild_id = data.guild_id or self.guild_id
    self.topic = data.topic
    if data.privacy_level ~= nil then
        self.privacy_level = data.privacy_level
    end
    if data.discoverable_disabled ~= nil then
        self.discoverable_disabled = data.discoverable_disabled
    else
        self.discoverable_disabled = self.discoverable_disabled or false
    end
    self.scheduled_event_id = data.guild_scheduled_event_id or self.scheduled_event_id
end

function StageInstance.new(data, guild, http)
    local self = {}
    setmetatable(self, { __index = StageInstance })

    apply(self, data)
    self.guild = guild
    self.guild_id = self.guild_id or (guild and guild.id)
    self.http = http or (guild and guild.http)

    return self
end

function StageInstance:edit(opts)
    opts = opts or {}
    if not self.http then
        error("StageInstance has no http client attached, cannot edit", 0)
    end

    local Route = require("../http/route")
    local route = Route.new(self.http)

    local payload = {}
    if opts.topic ~= nil then
        payload.topic = opts.topic
    end
    if opts.privacy_level ~= nil then
        payload.privacy_level = opts.privacy_level
    end

    route:edit_stage_instance(self.channel_id, payload, opts.reason)

    if opts.topic ~= nil then
        self.topic = opts.topic
    end
    if opts.privacy_level ~= nil then
        self.privacy_level = opts.privacy_level
    end

    return self
end

function StageInstance:delete(reason)
    if not self.http then
        error("StageInstance has no http client attached, cannot delete", 0)
    end

    local Route = require("../http/route")
    local route = Route.new(self.http)

    return route:delete_stage_instance(self.channel_id, reason)
end

return StageInstance
