-- lib/models/template.lua
-- Guild Template model for Discord API
--
-- Public Contract:
--   Template.new(data, http?) -> Template
--     Creates a new Template from a raw API payload. http is optional,
--     used by :sync/:edit/:delete.
--
--   Template:code / :uses (raw "usage_count") / :name / :description -> as raw
--   Template:creator -> table or nil
--     Raw "creator" user payload, NOT wrapped into a User instance --
--     matches this project's existing convention of keeping embedded
--     user payloads raw (see e.g. Message.author, Integration.user).
--   Template:created_at / :updated_at -> string or nil
--     Raw ISO 8601 timestamps, not parsed into a date/time value, same
--     style as Message.timestamp elsewhere in this project.
--   Template:source_guild -> Guild
--     Built via Guild.new(data.serialized_source_guild, http), the
--     partial guild payload the API embeds directly in the template
--     response. pycord instead first checks its guild cache
--     (state._get_guild) and only falls back to constructing a Guild
--     from serialized_source_guild when the guild isn't cached, using
--     a special _PartialTemplateState stub for the parts of Guild that
--     need a full ConnectionState. This project's Guild.new only ever
--     takes (data, http) and Client here holds no guild-by-id cache to
--     check against (see Client:get_guild, which reads gateway-fed
--     state.guilds, not a template-reachable store), so source_guild
--     is always built fresh from serialized_source_guild rather than
--     resolved against a live cache -- same no-cache stance used
--     throughout this session.
--   Template:is_dirty -> boolean or nil
--     Whether the template has unsynced changes.
--   Template:url -> string
--     "https://discord.new/{code}", mirrors pycord's Template.url.
--
--   Template:sync() -> Template (self)
--     PUT /guilds/{guild_id}/templates/{code} (source_guild.id).
--     Re-applies the response onto self, mirrors pycord's sync()
--     returning a new Template -- here self is mutated in place
--     instead, same as StageInstance:edit/ScheduledEvent:edit.
--   Template:edit(opts) -> Template (self)
--     PATCH /guilds/{guild_id}/templates/{code}. opts.name /
--     opts.description, both optional. Re-applies the response onto
--     self.
--   Template:delete() -> table
--     DELETE /guilds/{guild_id}/templates/{code}.
--
--   Client:fetch_template(code) -> Template
--     GET /guilds/templates/{code}, mirrors pycord's
--     Client.fetch_template(). code is a plain template code or a
--     discord.new URL -- resolved the same way as pycord's
--     utils.resolve_template (regex strips a discord.new/ prefix if
--     present, otherwise the string is used as-is).
--
--   Guild:fetch_templates() -> table of Template
--     GET /guilds/{guild_id}/templates, mirrors pycord's
--     Guild.templates().
--   Guild:create_template(opts) -> Template
--     POST /guilds/{guild_id}/templates. opts.name (required),
--     opts.description (optional), mirrors pycord's
--     Guild.create_template().

local class = require("../core/class")
local Guild = require("./guild")

local Template = class("Template")

local function apply(self, data, http)
    data = data or {}
    self.code = data.code or self.code
    self.uses = data.usage_count
    self.name = data.name
    self.description = data.description
    self.creator = data.creator
    self.created_at = data.created_at
    self.updated_at = data.updated_at
    self.is_dirty = data.is_dirty

    self.http = http or self.http
    if data.serialized_source_guild then
        local source = data.serialized_source_guild
        source.id = data.source_guild_id or source.id
        self.source_guild = Guild.new(source, self.http)
    elseif self.source_guild == nil and data.source_guild_id then
        self.source_guild = Guild.new({ id = data.source_guild_id }, self.http)
    end
end

function Template.new(data, http)
    local self = {}
    setmetatable(self, { __index = Template })
    apply(self, data, http)
    return self
end

function Template:url()
    return "https://discord.new/" .. self.code
end

function Template:sync()
    if not self.http then
        error("Template has no http client attached, cannot sync", 0)
    end
    if not (self.source_guild and self.source_guild.id) then
        error("Template has no source_guild, cannot sync", 0)
    end

    local Route = require("../http/route")
    local route = Route.new(self.http)

    local data = route:sync_template(self.source_guild.id, self.code)
    apply(self, data, self.http)
    return self
end

function Template:edit(opts)
    opts = opts or {}
    if not self.http then
        error("Template has no http client attached, cannot edit", 0)
    end
    if not (self.source_guild and self.source_guild.id) then
        error("Template has no source_guild, cannot edit", 0)
    end

    local Route = require("../http/route")
    local route = Route.new(self.http)

    local payload = {}
    if opts.name ~= nil then
        payload.name = opts.name
    end
    if opts.description ~= nil then
        payload.description = opts.description
    end

    local data = route:edit_template(self.source_guild.id, self.code, payload)
    apply(self, data, self.http)
    return self
end

function Template:delete()
    if not self.http then
        error("Template has no http client attached, cannot delete", 0)
    end
    if not (self.source_guild and self.source_guild.id) then
        error("Template has no source_guild, cannot delete", 0)
    end

    local Route = require("../http/route")
    local route = Route.new(self.http)

    return route:delete_template(self.source_guild.id, self.code)
end

return Template
