-- lib/gateway/opcodes.lua
-- Gateway opcodes for the Discord WebSocket protocol
-- Reference: https://discord.com/developers/docs/topics/opcodes-and-status-codes
--
-- Public Contract:
--   Opcodes: constant values used in the "op" field of every gateway payload
--     DISPATCH = 0          - server -> client, an event with t/d set (READY, MESSAGE_CREATE, ...)
--     HEARTBEAT = 1         - bidirectional, client sends on its own timer, server can request one
--     IDENTIFY = 2          - client -> server, starts a new session
--     PRESENCE_UPDATE = 3   - client -> server, update presence
--     VOICE_STATE_UPDATE = 4 - client -> server, join/leave/move voice channel
--     RESUME = 6            - client -> server, resume a closed session
--     RECONNECT = 7         - server -> client, client should reconnect and resume
--     REQUEST_GUILD_MEMBERS = 8 - client -> server
--     INVALID_SESSION = 9   - server -> client, session is invalid, reidentify or resume
--     HELLO = 10            - server -> client, contains heartbeat_interval, sent on connect
--     HEARTBEAT_ACK = 11    - server -> client, acknowledges a heartbeat

local DISPATCH = 0
local HEARTBEAT = 1
local IDENTIFY = 2
local PRESENCE_UPDATE = 3
local VOICE_STATE_UPDATE = 4
local RESUME = 6
local RECONNECT = 7
local REQUEST_GUILD_MEMBERS = 8
local INVALID_SESSION = 9
local HELLO = 10
local HEARTBEAT_ACK = 11

local M = {
    DISPATCH = DISPATCH,
    HEARTBEAT = HEARTBEAT,
    IDENTIFY = IDENTIFY,
    PRESENCE_UPDATE = PRESENCE_UPDATE,
    VOICE_STATE_UPDATE = VOICE_STATE_UPDATE,
    RESUME = RESUME,
    RECONNECT = RECONNECT,
    REQUEST_GUILD_MEMBERS = REQUEST_GUILD_MEMBERS,
    INVALID_SESSION = INVALID_SESSION,
    HELLO = HELLO,
    HEARTBEAT_ACK = HEARTBEAT_ACK,
}

return M
