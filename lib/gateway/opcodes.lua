-- lib/gateway/opcodes.lua
-- Gateway opcodes for Discord WebSocket protocol
--
-- Public Contract:
--   Opcodes: constant values for WebSocket messages
--     CONNECT = 0     - Initial handshake
--     IDENTIFY = 2    - Bot identification
--     READY = 10      - Ready event from Discord
--     HEARTBEAT = 1   - Heartbeat sent by bot
--     HEARTBEAT_ACK = 10 - Heartbeat acknowledgment
--     RESUME = 12     - Session resume
--     DISCONNECTED = 11 - Disconnection event
--     RECONNECT = 7   - Reconnect instruction

-- Opcodes
local CONNECT = 0
local IDENTIFY = 2
local READY = 10
local HEARTBEAT = 1
local HEARTBEAT_ACK = 10
local RESUME = 12
local DISCONNECTED = 11
local RECONNECT = 7

local M = {
    CONNECT = CONNECT,
    IDENTIFY = IDENTIFY,
    READY = READY,
    HEARTBEAT = HEARTBEAT,
    HEARTBEAT_ACK = HEARTBEAT_ACK,
    RESUME = RESUME,
    DISCONNECTED = DISCONNECTED,
    RECONNECT = RECONNECT,
}

return M
