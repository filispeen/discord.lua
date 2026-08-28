-- lib/models/audit_log.lua
-- Audit Log models for Discord API
--
-- Public Contract:
--   AuditLogChanges.new(changes_data?) -> AuditLogChanges
--     changes_data: raw array of { key, old_value?, new_value? } from
--     the audit log entry payload's "changes" field.
--
--   AuditLogChanges:before -> table
--   AuditLogChanges:after -> table
--     Plain key -> value tables built from the raw changes array. Unlike
--     pycord's AuditLogChanges, values here are NOT resolved into model
--     instances (Role/Member/Channel/etc) or renamed/type-converted --
--     this project's Guild model holds no member/role/channel cache to
--     resolve against (Guild.new only takes data + http, see
--     lib/models/guild.lua), so before/after simply mirror the API's
--     raw old_value/new_value under the original field name. The one
--     exception is the "$add"/"$remove" pseudo-keys pycord special
--     cases for role changes (used by MEMBER_ROLE_UPDATE entries): those
--     populate before.roles / after.roles with the delta role list
--     ({id, name} stubs, not resolved Role instances) rather than being
--     dropped, since that is the single most common real-world use of
--     AuditLogChanges and dropping it entirely would make role-change
--     entries silently useless.
--
--   AuditLogEntry.new(data, guild?, http?) -> AuditLogEntry
--     Creates a new AuditLogEntry from a raw API payload. guild is
--     optional (stored on self.guild, used for guild_id fallback). http
--     is optional, falls back to guild.http (unused for now, entries
--     have no mutating endpoints, kept for parity with other models).
--
--   AuditLogEntry:id / :guild_id -> string
--   AuditLogEntry:action_type -> number (raw AuditLogAction, see
--     Discord's Audit Log Action Type docs; this project does not
--     define an enum table for it, matching the style already used for
--     e.g. ScheduledEvent.status which is also a raw int)
--   AuditLogEntry:user_id -> string or nil
--     The user (usually a moderator) who performed the action. Kept as
--     a raw id, not resolved to a Member/User -- see note above.
--   AuditLogEntry:target_id -> string or nil
--     The id of whatever got changed. Its real type depends on
--     action_type (pycord resolves this via a per-action-category
--     converter into Guild/Role/Member/Channel/etc -- not done here for
--     the same no-cache reason as user_id).
--   AuditLogEntry:reason -> string or nil
--   AuditLogEntry:extra -> table or nil
--     Raw "options" field from the payload. pycord wraps this into one
--     of several proxy types depending on action_type (member_prune,
--     message_delete, overwrite_*, stage_instance_*, pin actions, etc).
--     Kept as the raw table here -- callers that need e.g.
--     extra.count/extra.channel_id can read it directly.
--   AuditLogEntry:changes -> AuditLogChanges
--
--   Guild:fetch_audit_logs(opts?) -> table of AuditLogEntry
--     See lib/models/guild.lua for opts and endpoint details.

local class = require("../core/class")

local AuditLogChanges = class("AuditLogChanges")
local AuditLogEntry = class("AuditLogEntry")

local function resolve_role(data, client)
    if client and client.roles and data and data.id then
        local cached = client.roles:get(data.guild_id, data.id)
        if cached then
            return require("./role").new(cached)
        end
    end
    return { id = data.id, name = data.name }
end

local function role_stubs(list, client, guild)
    local stubs = {}
    for _, role_data in ipairs(list or {}) do
        local data = role_data
        if client and guild and client.roles then
            data = client.roles:get(guild.id, role_data.id) or role_data
            data.guild_id = guild.id
        end
        table.insert(stubs, resolve_role(data, client))
    end
    return stubs
end

function AuditLogChanges.new(changes_data, client, guild)
    local self = {}
    setmetatable(self, { __index = AuditLogChanges })

    self.before = {}
    self.after = {}

    for _, elem in ipairs(changes_data or {}) do
        local key = elem.key
        if key == "$add" then
            if self.before.roles == nil then
                self.before.roles = {}
            end
            self.after.roles = role_stubs(elem.new_value, client, guild)
        elseif key == "$remove" then
            if self.after.roles == nil then
                self.after.roles = {}
            end
            self.before.roles = role_stubs(elem.new_value, client, guild)
        else
            if elem.old_value ~= nil then
                self.before[key] = elem.old_value
            end
            if elem.new_value ~= nil then
                self.after[key] = elem.new_value
            end
        end
    end

    return self
end

function AuditLogEntry.new(data, guild, http, client)
    local self = {}
    setmetatable(self, { __index = AuditLogEntry })

    data = data or {}
    self.id = data.id
    self.action_type = data.action_type
    self.user_id = data.user_id
    self.target_id = data.target_id
    self.reason = data.reason
    self.extra = data.options
    self.client = client or (guild and guild.client)
    self.changes = AuditLogChanges.new(data.changes, self.client, guild)

    self.guild = guild
    self.guild_id = data.guild_id or (guild and guild.id)
    self.http = http or (guild and guild.http)

    return self
end

return {
    AuditLogEntry = AuditLogEntry,
    AuditLogChanges = AuditLogChanges,
}
