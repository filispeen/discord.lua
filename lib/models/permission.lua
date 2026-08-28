local class = require("../core/class")
local bitwise = require("../core/bitwise")

local M = {}

local constants = {
    CREATE_INSTANT_INVITE = 1, KICK_MEMBERS = 2, BAN_MEMBERS = 4,
    ADMINISTRATOR = 8, MANAGE_CHANNELS = 16, MANAGE_GUILD = 32,
    ADD_REACTIONS = 64, VIEW_AUDIT_LOG = 128, PRIORITY_SPEAKER = 256,
    STREAM = 512, VIEW_CHANNEL = 1024, SEND_MESSAGES = 2048,
    SEND_TTS_MESSAGES = 4096, MANAGE_MESSAGES = 8192, EMBED_LINKS = 16384,
    ATTACH_FILES = 32768, READ_MESSAGE_HISTORY = 65536, MENTION_EVERYONE = 131072,
    USE_EXTERNAL_EMOJIS = 262144, VIEW_GUILD_INSIGHTS = 524288, CONNECT = 1048576,
    SPEAK = 2097152, MUTE_MEMBERS = 4194304, DEAFEN_MEMBERS = 8388608,
    MOVE_MEMBERS = 16777216, USE_VAD = 33554432, CHANGE_NICKNAME = 67108864,
    MANAGE_NICKNAMES = 134217728, MANAGE_ROLES = 268435456, MANAGE_WEBHOOKS = 536870912,
    MANAGE_GUILD_EXPRESSIONS = 1073741824, USE_APPLICATION_COMMANDS = 2147483648,
    REQUEST_TO_SPEAK = 4294967296, MANAGE_EVENTS = 8589934592, MANAGE_THREADS = 17179869184,
    CREATE_PUBLIC_THREADS = 34359738368, CREATE_PRIVATE_THREADS = 68719476736,
    USE_EXTERNAL_STICKERS = 137438953472, SEND_MESSAGES_IN_THREADS = 274877906944,
    USE_EMBEDDED_ACTIVITIES = 549755813888, MODERATE_MEMBERS = 1099511627776,
    VIEW_CREATOR_MONETIZATION_ANALYTICS = 2199023255552, USE_SOUNDBOARD = 4398046511104,
    CREATE_GUILD_EXPRESSIONS = 8796093022208, CREATE_EVENTS = 17592186044416,
    USE_EXTERNAL_SOUNDS = 35184372088832, SEND_VOICE_MESSAGES = 70368744177664,
    SEND_POLLS = 140737488355328, USE_EXTERNAL_APPS = 281474976710656,
}

for name, value in pairs(constants) do M[name] = value end
M.MANAGE_EMOJIS = M.MANAGE_GUILD_EXPRESSIONS
M.SEND_EMBEDDED_MESSAGES = M.EMBED_LINKS
M.SEND_INTEGRATIONS = M.USE_EXTERNAL_EMOJIS
M.USE_SLASH_COMMANDS = M.USE_APPLICATION_COMMANDS
M.band, M.bor, M.bnot = bitwise.band, bitwise.bor, bitwise.bnot

function M.has_permission(permissions, required)
    local value = type(permissions) == "table" and permissions.value or permissions
    return M.band(value, required) == required
end

function M.add_permission(permissions, perm) return M.bor(permissions, perm) end
function M.remove_permission(permissions, perm) return M.band(permissions, M.bnot(perm)) end
function M.check_administrator(permissions) return M.has_permission(permissions, M.ADMINISTRATOR) end

local Permissions = class("Permissions")

function Permissions.new(value, opts)
    if type(value) == "table" and opts == nil then opts, value = value, 0 end
    local self = { value = tonumber(value) or 0 }
    setmetatable(self, { __index = Permissions })
    for name, enabled in pairs(opts or {}) do self:set(name, enabled) end
    return self
end

function Permissions.none() return Permissions.new(0) end

function Permissions.all()
    local value = 0
    for _, flag in pairs(constants) do value = M.bor(value, flag) end
    return Permissions.new(value)
end

function Permissions:has(permission)
    local flag = type(permission) == "string" and constants[permission:upper()] or permission
    if not flag then error("unknown permission", 0) end
    return M.has_permission(self.value, flag)
end

function Permissions:set(permission, enabled)
    local flag = type(permission) == "string" and constants[permission:upper()] or permission
    if not flag then error("unknown permission", 0) end
    self.value = enabled == false and M.remove_permission(self.value, flag) or M.add_permission(self.value, flag)
    return self
end

function Permissions:update(opts)
    for permission, enabled in pairs(opts or {}) do self:set(permission, enabled) end
    return self
end

function Permissions:is_subset(other)
    local value = type(other) == "table" and other.value or other
    return M.band(self.value, value or 0) == self.value
end

function Permissions:is_superset(other)
    local value = type(other) == "table" and other.value or other
    return M.band(self.value, value or 0) == (value or 0)
end

function Permissions:handle_overwrite(allow, deny)
    self.value = M.bor(M.band(self.value, M.bnot(deny or 0)), allow or 0)
    return self
end

function Permissions:to_number() return self.value end

function Permissions:to_dict()
    local result = {}
    for name, flag in pairs(constants) do result[name:lower()] = self:has(flag) end
    return result
end

M.Permissions = Permissions

function M.can_manage_guild(permissions) return M.has_permission(permissions, M.MANAGE_GUILD) end
function M.can_manage_roles(permissions) return M.has_permission(permissions, M.MANAGE_ROLES) end
function M.can_manage_webhooks(permissions) return M.has_permission(permissions, M.MANAGE_WEBHOOKS) end
function M.can_manage_emojis(permissions) return M.has_permission(permissions, M.MANAGE_EMOJIS) end
function M.can_kick_members(permissions) return M.has_permission(permissions, M.KICK_MEMBERS) end
function M.can_ban_members(permissions) return M.has_permission(permissions, M.BAN_MEMBERS) end
function M.can_view_channel(permissions) return M.has_permission(permissions, M.VIEW_CHANNEL) end
function M.can_send_messages(permissions) return M.has_permission(permissions, M.SEND_MESSAGES) end
function M.can_send_tts_messages(permissions) return M.has_permission(permissions, M.SEND_TTS_MESSAGES) end
function M.can_send_embedded_messages(permissions) return M.has_permission(permissions, M.EMBED_LINKS) end
function M.can_attach_files(permissions) return M.has_permission(permissions, M.ATTACH_FILES) end
function M.can_read_message_history(permissions) return M.has_permission(permissions, M.READ_MESSAGE_HISTORY) end
function M.can_mention_everyone(permissions) return M.has_permission(permissions, M.MENTION_EVERYONE) end
function M.can_use_external_emojis(permissions) return M.has_permission(permissions, M.USE_EXTERNAL_EMOJIS) end

return M
