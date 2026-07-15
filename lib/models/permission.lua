-- lib/models/permission.lua
-- Permission Bitmath Utilities
--
-- Public Contract:
--   Permission constants: ADMINISTRATOR, VIEW_CHANNEL, SEND_MESSAGES, etc.
--   has_permission(permissions, required) -> boolean
--     Checks if permissions include required permission.
--   add_permission(permissions, perm) -> number
--     Adds a permission.
--   remove_permission(permissions, perm) -> number
--     Removes a permission.
--   check_administrator(permissions) -> boolean
--     Checks for administrator flag.

-- Permission constants (Discord API values)
local ADMINISTRATOR = 268435456
local MANAGE_GUILD = 2147483648
local MANAGE_ROLES = 2097152
local MANAGE_WEBHOOKS = 134217728
local MANAGE_EMOJIS = 65536
local MANAGE_MESSAGES = 2097152
local BANN_MEMBERS = 16
local KICK_MEMBERS = 8
local ADD_REACTIONS = 4194304
local VIEW_AUDIT_LOG = 16777216
local PRIORITY_SPEAKER = 1048576
local USE_EXTERNAL_EMOJIS = 524288
local VIEW_CHANNEL = 1024
local SEND_MESSAGES = 2048
local SEND_TTS_MESSAGES = 4096
local SEND_EMBEDDED_MESSAGES = 8192
local ATTACH_FILES = 16384
local READ_MESSAGE_HISTORY = 65536
local MENTION_EVERYONE = 131072
local USE_EXTERNAL_STICKERS = 1048576
local SEND_INTEGRATIONS = 524288
local USE_APPLICATION_COMMANDS = 1048576
local USE_SLASH_COMMANDS = 1048576

local M = {
    ADMINISTRATOR = ADMINISTRATOR,
    MANAGE_GUILD = MANAGE_GUILD,
    MANAGE_ROLES = MANAGE_ROLES,
    MANAGE_WEBHOOKS = MANAGE_WEBHOOKS,
    MANAGE_EMOJIS = MANAGE_EMOJIS,
    MANAGE_MESSAGES = MANAGE_MESSAGES,
    BANN_MEMBERS = BANN_MEMBERS,
    KICK_MEMBERS = KICK_MEMBERS,
    ADD_REACTIONS = ADD_REACTIONS,
    VIEW_AUDIT_LOG = VIEW_AUDIT_LOG,
    PRIORITY_SPEAKER = PRIORITY_SPEAKER,
    USE_EXTERNAL_EMOJIS = USE_EXTERNAL_EMOJIS,
    VIEW_CHANNEL = VIEW_CHANNEL,
    SEND_MESSAGES = SEND_MESSAGES,
    SEND_TTS_MESSAGES = SEND_TTS_MESSAGES,
    SEND_EMBEDDED_MESSAGES = SEND_EMBEDDED_MESSAGES,
    ATTACH_FILES = ATTACH_FILES,
    READ_MESSAGE_HISTORY = READ_MESSAGE_HISTORY,
    MENTION_EVERYONE = MENTION_EVERYONE,
    USE_EXTERNAL_STICKERS = USE_EXTERNAL_STICKERS,
    SEND_INTEGRATIONS = SEND_INTEGRATIONS,
    USE_APPLICATION_COMMANDS = USE_APPLICATION_COMMANDS,
    USE_SLASH_COMMANDS = USE_SLASH_COMMANDS,
}

-- Check if permissions include required permission (bitwise AND)
function M.has_permission(permissions, required)
    return (permissions & required) ~= 0
end

-- Add permission (bitwise OR)
function M.add_permission(permissions, perm)
    return permissions | perm
end

-- Remove permission (bitwise AND NOT)
function M.remove_permission(permissions, perm)
    return permissions & ~perm
end

-- Check for administrator flag
function M.check_administrator(permissions)
    return (permissions & ADMINISTRATOR) ~= 0
end

-- Check if can manage guild
function M.can_manage_guild(permissions)
    return M.has_permission(permissions, M.MANAGE_GUILD)
end

-- Check if can manage roles
function M.can_manage_roles(permissions)
    return M.has_permission(permissions, M.MANAGE_ROLES)
end

-- Check if can ban members
function M.can_ban_members(permissions)
    return M.has_permission(permissions, M.BANN_MEMBERS)
end

-- Check if can kick members
function M.can_kick_members(permissions)
    return M.has_permission(permissions, M.KICK_MEMBERS)
end

-- Check if can send messages
function M.can_send_messages(permissions)
    return M.has_permission(permissions, M.SEND_MESSAGES)
end

-- Check if can embed links
function M.can_send_embeds(permissions)
    return M.has_permission(permissions, M.SEND_EMBEDDED_MESSAGES)
end

-- Check if can attach files
function M.can_attach_files(permissions)
    return M.has_permission(permissions, M.ATTACH_FILES)
end

-- Check if can read message history
function M.can_read_message_history(permissions)
    return M.has_permission(permissions, M.READ_MESSAGE_HISTORY)
end

-- Check if can mention everyone
function M.can_mention_everyone(permissions)
    return M.has_permission(permissions, M.MENTION_EVERYONE)
end

-- Check if can use external emojies
function M.can_use_external_emojis(permissions)
    return M.has_permission(permissions, M.USE_EXTERNAL_EMOJIS)
end

-- Check if can use slash commands
function M.can_use_slash_commands(permissions)
    return M.has_permission(permissions, M.USE_SLASH_COMMANDS)
end

return M
