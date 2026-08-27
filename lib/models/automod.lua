-- lib/models/automod.lua
-- AutoMod models for Discord API
--
-- Public Contract:
--   AutoModActionMetadata.new(opts?) -> AutoModActionMetadata
--     opts.channel_id: for AutoModActionType.send_alert_message (2).
--     opts.timeout_duration: number of seconds, for
--     AutoModActionType.timeout (3) (pycord uses a timedelta, this
--     project just keeps plain seconds like elsewhere in the codebase).
--     opts.custom_message: for AutoModActionType.block_message (1).
--
--   AutoModActionMetadata:to_dict() -> table
--     Only includes fields that were actually set.
--
--   AutoModActionMetadata.from_dict(data) -> AutoModActionMetadata
--
--   AutoModAction.new(action_type, metadata) -> AutoModAction
--     action_type: AutoModActionType (1 block_message, 2
--     send_alert_message, 3 timeout). metadata: AutoModActionMetadata.
--
--   AutoModAction:to_dict() -> table
--   AutoModAction.from_dict(data) -> AutoModAction
--
--   AutoModTriggerMetadata.new(opts?) -> AutoModTriggerMetadata
--     opts.keyword_filter / opts.regex_patterns / opts.presets /
--     opts.allow_list / opts.mention_total_limit, all optional, see
--     table in pycord's automod.py for which trigger types use which.
--
--   AutoModTriggerMetadata:to_dict() -> table
--     Only includes fields that were actually set.
--
--   AutoModTriggerMetadata.from_dict(data) -> AutoModTriggerMetadata
--
--   AutoModRule.new(data, guild, http) -> AutoModRule
--     Creates a new AutoModRule from a raw API payload. guild is
--     optional (stored on self.guild). http is optional, falls back
--     to guild.http.
--
--   AutoModRule:id / :guild_id / :name / :creator_id -> as raw
--   AutoModRule:event_type -> number (AutoModEventType: 1 message_send)
--   AutoModRule:trigger_type -> number
--     AutoModTriggerType: 1 keyword, 2 harmful_link, 3 spam,
--     4 keyword_preset, 5 mention_spam. Immutable after creation,
--     :edit() below intentionally has no way to change it (matches
--     the Discord API / pycord's AutoModRule.edit()).
--   AutoModRule:trigger_metadata -> AutoModTriggerMetadata
--   AutoModRule:actions -> table (array of AutoModAction)
--   AutoModRule:enabled -> boolean
--   AutoModRule:exempt_role_ids -> table (array of role id strings)
--   AutoModRule:exempt_channel_ids -> table (array of channel id strings)
--
--   AutoModRule:edit(opts) -> AutoModRule (self)
--     PATCH /guilds/{guild_id}/auto-moderation/rules/{id}. opts: name /
--     event_type / trigger_metadata (an AutoModTriggerMetadata) /
--     actions (array of AutoModAction) / enabled / exempt_role_ids /
--     exempt_channel_ids / reason. Updates self in place from the
--     response.
--
--   AutoModRule:delete(reason?) -> table
--     DELETE /guilds/{guild_id}/auto-moderation/rules/{id}.

local class = require("../core/class")

local AutoModActionMetadata = class("AutoModActionMetadata")
local AutoModAction = class("AutoModAction")
local AutoModTriggerMetadata = class("AutoModTriggerMetadata")
local AutoModRule = class("AutoModRule")

function AutoModActionMetadata.new(opts)
    opts = opts or {}
    local self = {}
    setmetatable(self, { __index = AutoModActionMetadata })
    self.channel_id = opts.channel_id
    self.timeout_duration = opts.timeout_duration
    self.custom_message = opts.custom_message
    return self
end

function AutoModActionMetadata:to_dict()
    local dict = {}
    if self.channel_id ~= nil then
        dict.channel_id = self.channel_id
    end
    if self.timeout_duration ~= nil then
        dict.duration_seconds = self.timeout_duration
    end
    if self.custom_message ~= nil then
        dict.custom_message = self.custom_message
    end
    return dict
end

function AutoModActionMetadata.from_dict(data)
    data = data or {}
    return AutoModActionMetadata.new({
        channel_id = data.channel_id,
        timeout_duration = data.duration_seconds,
        custom_message = data.custom_message,
    })
end

function AutoModAction.new(action_type, metadata)
    local self = {}
    setmetatable(self, { __index = AutoModAction })
    self.type = action_type
    self.metadata = metadata or AutoModActionMetadata.new()
    return self
end

function AutoModAction:to_dict()
    return { type = self.type, metadata = self.metadata:to_dict() }
end

function AutoModAction.from_dict(data)
    return AutoModAction.new(data.type, AutoModActionMetadata.from_dict(data.metadata))
end

function AutoModTriggerMetadata.new(opts)
    opts = opts or {}
    local self = {}
    setmetatable(self, { __index = AutoModTriggerMetadata })
    self.keyword_filter = opts.keyword_filter
    self.regex_patterns = opts.regex_patterns
    self.presets = opts.presets
    self.allow_list = opts.allow_list
    self.mention_total_limit = opts.mention_total_limit
    return self
end

function AutoModTriggerMetadata:to_dict()
    local dict = {}
    if self.keyword_filter ~= nil then
        dict.keyword_filter = self.keyword_filter
    end
    if self.regex_patterns ~= nil then
        dict.regex_patterns = self.regex_patterns
    end
    if self.presets ~= nil then
        dict.presets = self.presets
    end
    if self.allow_list ~= nil then
        dict.allow_list = self.allow_list
    end
    if self.mention_total_limit ~= nil then
        dict.mention_total_limit = self.mention_total_limit
    end
    return dict
end

function AutoModTriggerMetadata.from_dict(data)
    data = data or {}
    return AutoModTriggerMetadata.new({
        keyword_filter = data.keyword_filter,
        regex_patterns = data.regex_patterns,
        presets = data.presets,
        allow_list = data.allow_list,
        mention_total_limit = data.mention_total_limit,
    })
end

local function apply(self, data)
    self.id = data.id
    self.guild_id = data.guild_id or self.guild_id
    self.name = data.name
    self.creator_id = data.creator_id
    self.event_type = data.event_type
    self.trigger_type = data.trigger_type or self.trigger_type
    self.trigger_metadata = AutoModTriggerMetadata.from_dict(data.trigger_metadata)

    self.actions = {}
    for _, action_data in ipairs(data.actions or {}) do
        table.insert(self.actions, AutoModAction.from_dict(action_data))
    end

    self.enabled = data.enabled or false
    self.exempt_role_ids = data.exempt_roles or {}
    self.exempt_channel_ids = data.exempt_channels or {}
end

function AutoModRule.new(data, guild, http)
    local self = {}
    setmetatable(self, {
        __index = AutoModRule
    })

    apply(self, data)
    self.guild = guild
    self.guild_id = self.guild_id or (guild and guild.id)
    self.http = http or (guild and guild.http)

    return self
end

function AutoModRule:edit(opts)
    opts = opts or {}
    if not self.http then
        error("AutoModRule has no http client attached, cannot edit", 0)
    end

    local payload = {}
    if opts.name ~= nil then
        payload.name = opts.name
    end
    if opts.event_type ~= nil then
        payload.event_type = opts.event_type
    end
    if opts.trigger_metadata ~= nil then
        payload.trigger_metadata = opts.trigger_metadata:to_dict()
    end
    if opts.actions ~= nil then
        local actions = {}
        for _, action in ipairs(opts.actions) do
            table.insert(actions, action:to_dict())
        end
        payload.actions = actions
    end
    if opts.enabled ~= nil then
        payload.enabled = opts.enabled
    end
    if opts.exempt_role_ids ~= nil then
        payload.exempt_roles = opts.exempt_role_ids
    end
    if opts.exempt_channel_ids ~= nil then
        payload.exempt_channels = opts.exempt_channel_ids
    end

    local request_opts = opts.reason and { reason = opts.reason } or nil
    local endpoint = "/guilds/" .. self.guild_id .. "/auto-moderation/rules/" .. self.id
    local updated = self.http:patch(endpoint, payload, request_opts)
    if type(updated) == "table" then
        apply(self, updated)
    end
    return self
end

function AutoModRule:delete(reason)
    if not self.http then
        error("AutoModRule has no http client attached, cannot delete", 0)
    end
    local endpoint = "/guilds/" .. self.guild_id .. "/auto-moderation/rules/" .. self.id
    return self.http:delete(endpoint, reason and { reason = reason } or nil)
end

return {
    AutoModRule = AutoModRule,
    AutoModAction = AutoModAction,
    AutoModActionMetadata = AutoModActionMetadata,
    AutoModTriggerMetadata = AutoModTriggerMetadata,
}
