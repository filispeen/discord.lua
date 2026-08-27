-- lib/models/integration.lua
-- Guild Integration models for Discord API
--
-- Public Contract:
--   IntegrationAccount.new(data) -> IntegrationAccount
--     .id / .name, straight passthrough of the payload's "account" field.
--
--   IntegrationApplication.new(data) -> IntegrationApplication
--     .id / .name / .icon / .description / .summary / .user (raw "bot"
--     user payload table from the API, or nil -- see the note on
--     Integration.user below for why this stays a raw table).
--
--   Integration.new(data, guild?, http?) -> Integration
--     Base guild integration, covers plain (non-stream, non-bot) types.
--     guild is optional (stored on self.guild, used for guild_id
--     fallback). http is optional, falls back to guild.http.
--
--   Integration:id / :guild_id / :type / :name / :enabled -> as raw
--   Integration:account -> IntegrationAccount
--   Integration:user -> table or nil
--     Raw "user" payload from the API (whoever added the integration),
--     NOT wrapped into a User instance -- matches this project's
--     existing convention of keeping embedded user payloads raw rather
--     than constructing model instances for them (e.g. Message.author
--     in message.lua is also the raw payload table, despite its own
--     doc comment saying "-> User").
--
--   Integration:delete(reason?) -> table
--     DELETE /guilds/{guild_id}/integrations/{id}. Inherited by
--     StreamIntegration and BotIntegration below.
--
--   StreamIntegration.new(data, guild?, http?) -> StreamIntegration
--     Twitch/YouTube integrations, subclasses Integration (same base
--     fields plus the ones below).
--   StreamIntegration:revoked -> boolean
--   StreamIntegration:expire_behaviour -> number or nil
--     Raw ExpireBehaviour int (0 remove_role, 1 kick) straight off the
--     API's "expire_behavior" field. No enum table, same style as e.g.
--     ScheduledEvent.status.
--   StreamIntegration:expire_grace_period -> number (days)
--   StreamIntegration:synced_at -> string
--     Raw ISO 8601 timestamp, not parsed into a date/time value -- same
--     style as Message.timestamp elsewhere in this project.
--   StreamIntegration:role_id -> string or nil
--     Raw "role_id", NOT resolved to a Role instance. Guild here holds
--     no role cache to resolve against on a bare Guild.new (the live
--     cache lives in client.lua's role_store, out of reach from a
--     model built off a plain HTTP response) -- same no-cache stance
--     used throughout this session (see e.g. AuditLogChanges).
--   StreamIntegration:syncing / :enable_emoticons / :subscriber_count -> as raw
--
--   StreamIntegration:edit(opts) -> StreamIntegration (self)
--     PATCH /guilds/{guild_id}/integrations/{id} -- an undocumented
--     Discord endpoint (pycord's own comment on edit_integration notes
--     this too). opts.expire_behaviour / opts.expire_grace_period /
--     opts.enable_emoticons, all optional. The endpoint returns no
--     body, so self is patched locally from opts, same as
--     StageInstance:edit.
--   StreamIntegration:sync() -> StreamIntegration (self)
--     POST /guilds/{guild_id}/integrations/{id}/sync. Updates
--     self.synced_at to the current UTC time locally afterwards (same
--     as pycord, which also sets the timestamp client-side since the
--     endpoint returns no body).
--
--   BotIntegration.new(data, guild?, http?) -> BotIntegration
--     Discord application (bot) integrations, subclasses Integration.
--   BotIntegration:application -> IntegrationApplication
--
--   from_data(data, guild?, http?) -> Integration/StreamIntegration/BotIntegration
--     Picks the concrete class by data.type, mirrors pycord's
--     _integration_factory: "discord" -> BotIntegration,
--     "twitch"/"youtube" -> StreamIntegration, anything else ->
--     base Integration.
--
--   Guild:fetch_integrations() -> table of Integration/StreamIntegration/BotIntegration
--     GET /guilds/{guild_id}/integrations, mirrors pycord's
--     Guild.integrations().

local class = require("../core/class")

local Integration = class("Integration")
local StreamIntegration = class("StreamIntegration", Integration)
local BotIntegration = class("BotIntegration", Integration)
local IntegrationAccount = class("IntegrationAccount")
local IntegrationApplication = class("IntegrationApplication")

function IntegrationAccount.new(data)
    data = data or {}
    local self = {}
    setmetatable(self, { __index = IntegrationAccount })
    self.id = data.id
    self.name = data.name
    return self
end

function IntegrationApplication.new(data)
    data = data or {}
    local self = {}
    setmetatable(self, { __index = IntegrationApplication })
    self.id = data.id
    self.name = data.name
    self.icon = data.icon
    self.description = data.description
    self.summary = data.summary
    self.user = data.bot
    return self
end

local function apply_base(self, data, guild, http)
    data = data or {}
    self.id = data.id
    self.type = data.type
    self.name = data.name
    self.account = IntegrationAccount.new(data.account)
    self.user = data.user
    self.enabled = data.enabled or false

    self.guild = guild
    self.guild_id = data.guild_id or self.guild_id or (guild and guild.id)
    self.http = http or (guild and guild.http)
end

function Integration.new(data, guild, http)
    local self = {}
    setmetatable(self, { __index = Integration })
    apply_base(self, data, guild, http)
    return self
end

function Integration:delete(reason)
    if not self.http then
        error("Integration has no http client attached, cannot delete", 0)
    end

    local Route = require("../http/route")
    local route = Route.new(self.http)
    return route:delete_integration(self.guild_id, self.id, reason)
end

function StreamIntegration.new(data, guild, http)
    data = data or {}
    local self = {}
    setmetatable(self, { __index = StreamIntegration })
    apply_base(self, data, guild, http)

    self.revoked = data.revoked or false
    self.expire_behaviour = data.expire_behavior
    self.expire_grace_period = data.expire_grace_period
    self.synced_at = data.synced_at
    self.role_id = data.role_id
    self.syncing = data.syncing or false
    self.enable_emoticons = data.enable_emoticons
    self.subscriber_count = data.subscriber_count

    return self
end

function StreamIntegration:edit(opts)
    opts = opts or {}
    if not self.http then
        error("StreamIntegration has no http client attached, cannot edit", 0)
    end

    local Route = require("../http/route")
    local route = Route.new(self.http)

    local payload = {}
    if opts.expire_behaviour ~= nil then
        payload.expire_behavior = opts.expire_behaviour
    end
    if opts.expire_grace_period ~= nil then
        payload.expire_grace_period = opts.expire_grace_period
    end
    if opts.enable_emoticons ~= nil then
        payload.enable_emoticons = opts.enable_emoticons
    end

    route:edit_integration(self.guild_id, self.id, payload)

    if opts.expire_behaviour ~= nil then
        self.expire_behaviour = opts.expire_behaviour
    end
    if opts.expire_grace_period ~= nil then
        self.expire_grace_period = opts.expire_grace_period
    end
    if opts.enable_emoticons ~= nil then
        self.enable_emoticons = opts.enable_emoticons
    end

    return self
end

function StreamIntegration:sync()
    if not self.http then
        error("StreamIntegration has no http client attached, cannot sync", 0)
    end

    local Route = require("../http/route")
    local route = Route.new(self.http)
    route:sync_integration(self.guild_id, self.id)

    self.synced_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
    return self
end

function BotIntegration.new(data, guild, http)
    data = data or {}
    local self = {}
    setmetatable(self, { __index = BotIntegration })
    apply_base(self, data, guild, http)

    self.application = IntegrationApplication.new(data.application)

    return self
end

local function from_data(data, guild, http)
    data = data or {}
    local integration_type = data.type

    if integration_type == "discord" then
        return BotIntegration.new(data, guild, http)
    elseif integration_type == "twitch" or integration_type == "youtube" then
        return StreamIntegration.new(data, guild, http)
    else
        return Integration.new(data, guild, http)
    end
end

return {
    Integration = Integration,
    StreamIntegration = StreamIntegration,
    BotIntegration = BotIntegration,
    IntegrationAccount = IntegrationAccount,
    IntegrationApplication = IntegrationApplication,
    from_data = from_data,
}
