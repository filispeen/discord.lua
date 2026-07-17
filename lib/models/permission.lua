-- lib/models/permission.lua
-- Permission bitmath utilities for Discord roles

local M = {}

-- Permission constants (from Discord API)
M.ADMINISTRATOR = 268435456
M.MANAGE_GUILD = 2147483648
M.MANAGE_ROLES = 2097152
M.MANAGE_WEBHOOKS = 134217728
M.MANAGE_EMOJIS = 65536
M.KICK_MEMBERS = 8
M.BAN_MEMBERS = 16
M.VIEW_CHANNEL = 1024
M.SEND_MESSAGES = 2048
M.SEND_TTS_MESSAGES = 4096
M.SEND_EMBEDDED_MESSAGES = 8192
M.ATTACH_FILES = 16384
M.READ_MESSAGE_HISTORY = 65536
M.MENTION_EVERYONE = 131072
M.USE_EXTERNAL_EMOJIS = 524288
M.SEND_INTEGRATIONS = 524288
M.USE_APPLICATION_COMMANDS = 1048576
M.USE_SLASH_COMMANDS = 1048576

-- Bitwise AND (manual implementation)
function M.band(a, b)
    if not a or not b then return 0 end
    local result = 0
    local mask = 1
    while a > 0 or b > 0 do
        if (a % 2 == 1) and (b % 2 == 1) then
            result = result + mask
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        mask = mask * 2
    end
    return result
end

-- Bitwise OR (manual implementation)
function M.bor(a, b)
    local result = 0
    local mask = 1
    while a > 0 or b > 0 do
        if (a % 2 == 1) or (b % 2 == 1) then
            result = result + mask
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        mask = mask * 2
    end
    return result
end

-- Bitwise NOT (manual implementation for 32-bit)
function M.bnot(a)
    local result = 0
    local mask = 1
    for _ = 1, 32 do
        if (a % 2 == 0) then
            result = result + mask
        end
        a = math.floor(a / 2)
        mask = mask * 2
    end
    return result
end

-- Check if permissions include required permission (bitwise AND)
function M.has_permission(permissions, required)
    return M.band(permissions, required) ~= 0
end

-- Add permission (bitwise OR)
function M.add_permission(permissions, perm)
    return M.bor(permissions, perm)
end

-- Remove permission (bitwise AND NOT)
function M.remove_permission(permissions, perm)
    return M.band(permissions, M.bnot(perm))
end

-- Check if role has administrator permission
function M.check_administrator(permissions)
    return M.has_permission(permissions, M.ADMINISTRATOR)
end

-- Convenience functions
function M.can_manage_guild(permissions)
    return M.has_permission(permissions, M.MANAGE_GUILD)
end

function M.can_manage_roles(permissions)
    return M.has_permission(permissions, M.MANAGE_ROLES)
end

function M.can_manage_webhooks(permissions)
    return M.has_permission(permissions, M.MANAGE_WEBHOOKS)
end

function M.can_manage_emojis(permissions)
    return M.has_permission(permissions, M.MANAGE_EMOJIS)
end

function M.can_kick_members(permissions)
    return M.has_permission(permissions, M.KICK_MEMBERS)
end

function M.can_ban_members(permissions)
    return M.has_permission(permissions, M.BAN_MEMBERS)
end

function M.can_view_channel(permissions)
    return M.has_permission(permissions, M.VIEW_CHANNEL)
end

function M.can_send_messages(permissions)
    return M.has_permission(permissions, M.SEND_MESSAGES)
end

function M.can_send_tts_messages(permissions)
    return M.has_permission(permissions, M.SEND_TTS_MESSAGES)
end

function M.can_send_embedded_messages(permissions)
    return M.has_permission(permissions, M.SEND_EMBEDDED_MESSAGES)
end

function M.can_attach_files(permissions)
    return M.has_permission(permissions, M.ATTACH_FILES)
end

function M.can_read_message_history(permissions)
    return M.has_permission(permissions, M.READ_MESSAGE_HISTORY)
end

function M.can_mention_everyone(permissions)
    return M.has_permission(permissions, M.MENTION_EVERYONE)
end

function M.can_use_external_emojis(permissions)
    return M.has_permission(permissions, M.USE_EXTERNAL_EMOJIS)
end

return M
