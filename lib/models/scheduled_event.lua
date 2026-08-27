-- lib/models/scheduled_event.lua
-- ScheduledEvent model for Discord API
--
-- Public Contract:
--   ScheduledEvent.new(data, guild, http) -> ScheduledEvent
--     Creates a new ScheduledEvent from a raw API payload. guild is
--     optional (stored on self.guild, its id backs self.guild_id when
--     the payload omits one). http is optional, falls back to guild.http.
--
--   ScheduledEvent:id / :guild_id / :name / :description -> as raw
--
--   ScheduledEvent:start_time -> string (ISO 8601, scheduled_start_time)
--   ScheduledEvent:end_time -> string or nil (scheduled_end_time)
--
--   ScheduledEvent:status -> number
--     ScheduledEventStatus: 1 scheduled, 2 active, 3 completed, 4 canceled.
--
--   ScheduledEvent:privacy_level -> number
--   ScheduledEvent:subscriber_count -> number or nil (raw user_count)
--   ScheduledEvent:creator_id -> string or nil
--   ScheduledEvent:creator -> table or nil (raw user payload)
--
--   ScheduledEvent:entity_type -> number
--     ScheduledEventLocationType: 1 stage_instance, 2 voice, 3 external.
--
--   ScheduledEvent:channel_id -> string or nil
--     Set for stage_instance/voice entity_type events.
--
--   ScheduledEvent:location -> string or nil
--     External location text, from entity_metadata.location. Only set
--     for entity_type external events, use channel_id otherwise.
--
--   ScheduledEvent:edit(opts) -> ScheduledEvent (self)
--     PATCH /guilds/{guild_id}/scheduled-events/{id}. opts: name /
--     description / status / privacy_level / start_time / end_time /
--     reason, plus exactly one of:
--       opts.channel_id (+ opts.entity_type, default 2 = voice)
--       opts.location (sets entity_type=external + entity_metadata)
--     Updates self in place from the response.
--
--   ScheduledEvent:start(reason?) -> ScheduledEvent (self)
--   ScheduledEvent:complete(reason?) -> ScheduledEvent (self)
--   ScheduledEvent:cancel(reason?) -> ScheduledEvent (self)
--     Shorthands for edit(status = 2/3/4).
--
--   ScheduledEvent:delete() -> table
--     DELETE /guilds/{guild_id}/scheduled-events/{id}.
--
--   ScheduledEvent:fetch_subscribers(opts?) -> table
--     GET /guilds/{guild_id}/scheduled-events/{id}/users. opts.limit
--     (default 100) / opts.with_member / opts.before / opts.after,
--     all optional.

local class = require("../core/class")

local ScheduledEvent = class("ScheduledEvent")

local function apply(self, data)
    self.id = data.id
    self.guild_id = data.guild_id or self.guild_id
    self.name = data.name
    self.description = data.description
    self.start_time = data.scheduled_start_time
    self.end_time = data.scheduled_end_time
    self.status = data.status
    self.privacy_level = data.privacy_level
    self.subscriber_count = data.user_count
    self.creator_id = data.creator_id
    self.creator = data.creator
    self.entity_type = data.entity_type
    self.channel_id = data.channel_id

    local metadata = data.entity_metadata
    self.location = metadata and metadata.location or nil
end

function ScheduledEvent.new(data, guild, http)
    local self = {}
    setmetatable(self, {
        __index = ScheduledEvent
    })

    apply(self, data)
    self.guild = guild
    self.guild_id = self.guild_id or (guild and guild.id)
    self.http = http or (guild and guild.http)

    return self
end

function ScheduledEvent:edit(opts)
    opts = opts or {}
    if not self.http then
        error("ScheduledEvent has no http client attached, cannot edit", 0)
    end

    local payload = {}
    if opts.name ~= nil then
        payload.name = opts.name
    end
    if opts.description ~= nil then
        payload.description = opts.description
    end
    if opts.status ~= nil then
        payload.status = opts.status
    end
    if opts.privacy_level ~= nil then
        payload.privacy_level = opts.privacy_level
    end
    if opts.start_time ~= nil then
        payload.scheduled_start_time = opts.start_time
    end
    if opts.end_time ~= nil then
        payload.scheduled_end_time = opts.end_time
    end
    if opts.channel_id ~= nil then
        payload.channel_id = opts.channel_id
        payload.entity_type = opts.entity_type or 2
        payload.entity_metadata = nil
    end
    if opts.location ~= nil then
        payload.channel_id = nil
        payload.entity_type = 3
        payload.entity_metadata = { location = opts.location }
    end

    local request_opts = opts.reason and { reason = opts.reason } or nil
    local endpoint = "/guilds/" .. self.guild_id .. "/scheduled-events/" .. self.id
    local updated = self.http:patch(endpoint, payload, request_opts)
    if type(updated) == "table" then
        apply(self, updated)
    end
    return self
end

function ScheduledEvent:start(reason)
    return self:edit({ status = 2, reason = reason })
end

function ScheduledEvent:complete(reason)
    return self:edit({ status = 3, reason = reason })
end

function ScheduledEvent:cancel(reason)
    return self:edit({ status = 4, reason = reason })
end

function ScheduledEvent:delete()
    if not self.http then
        error("ScheduledEvent has no http client attached, cannot delete", 0)
    end
    return self.http:delete("/guilds/" .. self.guild_id .. "/scheduled-events/" .. self.id)
end

function ScheduledEvent:fetch_subscribers(opts)
    opts = opts or {}
    if not self.http then
        error("ScheduledEvent has no http client attached, cannot fetch_subscribers", 0)
    end

    local parts = {
        "limit=" .. tostring(opts.limit or 100),
        "with_member=" .. (opts.with_member and "1" or "0"),
    }
    if opts.before then
        table.insert(parts, "before=" .. tostring(opts.before))
    end
    if opts.after then
        table.insert(parts, "after=" .. tostring(opts.after))
    end

    local endpoint = "/guilds/" .. self.guild_id .. "/scheduled-events/" .. self.id ..
        "/users?" .. table.concat(parts, "&")
    return self.http:get(endpoint)
end

return ScheduledEvent
