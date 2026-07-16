-- lib/voice/enums.lua
-- Voice gateway opcodes and constants for Discord voice protocol
--
-- Public Contract:
--   Voice opcodes for WebSocket messages
--     IDENTIFY = 0      - Authenticate to voice gateway
--     SELECT_PROTOCOL = 1 - Request protocol (UDP)
--     READY = 2         - Server sends IP, port, modes
--     HEARTBEAT = 3     - Keep-alive
--     SESSION_DESCRIPTION = 4 - Send encrypted session key
--     SPEAKING = 5      - Notify speaking state
--     HEARTBEAT_ACK = 6 - Acknowledge heartbeat
--     RESUME = 7        - Resume existing connection
--     HELLO = 8         - Server sends heartbeat interval
--     RESUMED = 9       - Connection resumed
--     CLIENTS_CONNECT = 11 - Users connecting
--     CLIENT_CONNECT = 12 - User connected event
--     CLIENT_DISCONNECT = 13 - User disconnected
--
--   Supported encryption modes
--     XSALSA20_POLY1305_SUFFIX - AEAD encryption with suffix scheme
--     AEAD_XCHACHA20_POLY1305_RTPSIZE - XChaCha20-Poly1305 with RTP size

-- Voice Gateway OpCodes
local IDENTIFY = 0
local SELECT_PROTOCOL = 1
local READY = 2
local HEARTBEAT = 3
local SESSION_DESCRIPTION = 4
local SPEAKING = 5
local HEARTBEAT_ACK = 6
local RESUME = 7
local HELLO = 8
local RESUMED = 9
local CLIENTS_CONNECT = 11
local CLIENT_CONNECT = 12
local CLIENT_DISCONNECT = 13

-- Encryption modes (Discord supports multiple, using modern AEAD)
local SUPPORTED_MODES = {
    "xsalsa20_poly1305_suffix",
    "aead_xchacha20_poly1305_rtpsize",
}

-- Connection flow states
local DISCONNECTED = 0
local SET_GUILD_VOICE_STATE = 1
local GOT_VOICE_STATE_UPDATE = 2
local GOT_VOICE_SERVER_UPDATE = 3
local GOT_BOTH_VOICE_UPDATES = 4
local WEBSOCKET_CONNECTED = 5
local GOT_WEBSOCKET_READY = 6
local GOT_IP_DISCOVERY = 7
local CONNECTED = 8

local M = {
    -- Opcodes
    IDENTIFY = IDENTIFY,
    SELECT_PROTOCOL = SELECT_PROTOCOL,
    READY = READY,
    HEARTBEAT = HEARTBEAT,
    SESSION_DESCRIPTION = SESSION_DESCRIPTION,
    SPEAKING = SPEAKING,
    HEARTBEAT_ACK = HEARTBEAT_ACK,
    RESUME = RESUME,
    HELLO = HELLO,
    RESUMED = RESUMED,
    CLIENTS_CONNECT = CLIENTS_CONNECT,
    CLIENT_CONNECT = CLIENT_CONNECT,
    CLIENT_DISCONNECT = CLIENT_DISCONNECT,

    -- Encryption modes
    SUPPORTED_MODES = SUPPORTED_MODES,

    -- Connection states
    DISCONNECTED = DISCONNECTED,
    SET_GUILD_VOICE_STATE = SET_GUILD_VOICE_STATE,
    GOT_VOICE_STATE_UPDATE = GOT_VOICE_STATE_UPDATE,
    GOT_VOICE_SERVER_UPDATE = GOT_VOICE_SERVER_UPDATE,
    GOT_BOTH_VOICE_UPDATES = GOT_BOTH_VOICE_UPDATES,
    WEBSOCKET_CONNECTED = WEBSOCKET_CONNECTED,
    GOT_WEBSOCKET_READY = GOT_WEBSOCKET_READY,
    GOT_IP_DISCOVERY = GOT_IP_DISCOVERY,
    CONNECTED = CONNECTED,
}

return M
