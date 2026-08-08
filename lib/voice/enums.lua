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
--
--   DAVE (E2EE) opcodes, sent/received once max_dave_protocol_version > 0
--   has been negotiated in IDENTIFY and a session_description with a
--   dave_protocol_version > 0 has been received. JSON opcodes 21-24,
--   binary opcodes 25-31 (see lib/voice/dave_session.lua for the state
--   machine that drives these).
--     DAVE_PREPARE_TRANSITION = 21   - Discord announces an upcoming
--       protocol version change (JSON)
--     DAVE_EXECUTE_TRANSITION = 22   - Discord says to apply a
--       previously prepared transition now (JSON)
--     DAVE_TRANSITION_READY = 23     - Client acks readiness for a
--       transition (JSON, sent by us)
--     DAVE_PREPARE_EPOCH = 24        - Discord announces a new MLS
--       epoch/group is starting (JSON)
--     MLS_EXTERNAL_SENDER_PACKAGE = 25 - Discord's external sender
--       credential for the group (binary, received)
--     MLS_KEY_PACKAGE = 26           - Our serialized MLS key package
--       (binary, sent by us)
--     MLS_PROPOSALS = 27             - MLS proposals to add/remove
--       members (binary, received)
--     MLS_COMMIT_WELCOME = 28        - Our commit+welcome response to
--       proposals (binary, sent by us)
--     MLS_COMMIT_TRANSITION = 29     - MLS commit for an announced
--       transition (binary, received)
--     MLS_WELCOME = 30               - MLS welcome message to join the
--       group (binary, received)
--     MLS_INVALID_COMMIT_WELCOME = 31 - Sent by us when we failed to
--       process a commit/welcome, asking Discord to recover us (binary,
--       sent by us)

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

-- DAVE (E2EE) opcodes
local DAVE_PREPARE_TRANSITION = 21
local DAVE_EXECUTE_TRANSITION = 22
local DAVE_TRANSITION_READY = 23
local DAVE_PREPARE_EPOCH = 24
local MLS_EXTERNAL_SENDER_PACKAGE = 25
local MLS_KEY_PACKAGE = 26
local MLS_PROPOSALS = 27
local MLS_COMMIT_WELCOME = 28
local MLS_COMMIT_TRANSITION = 29
local MLS_WELCOME = 30
local MLS_INVALID_COMMIT_WELCOME = 31

-- Encryption modes (Discord supports multiple, using modern AEAD)
-- aead_xchacha20_poly1305_rtpsize is Discord's required voice
-- encryption mode (always present in Ready's modes list per Discord's
-- docs). xsalsa20_poly1305_suffix and every other legacy mode were
-- discontinued November 18th, 2024 and are no longer accepted by the
-- voice gateway (connecting with one closes with 4016 Unknown
-- encryption mode); listed here only in case a future fallback needs
-- it (see crypto.lua's legacy secretbox API, kept for reference).
local SUPPORTED_MODES = {
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

-- Voice gateway WebSocket close codes (from Discord's voice close code
-- reference). Used to decide whether a dropped connection should
-- RESUME, fall back to a fresh IDENTIFY, or not reconnect at all.
local CLOSE_UNKNOWN_OPCODE = 4001
local CLOSE_FAILED_TO_DECODE = 4002
local CLOSE_NOT_AUTHENTICATED = 4003
local CLOSE_AUTHENTICATION_FAILED = 4004
local CLOSE_ALREADY_AUTHENTICATED = 4005
local CLOSE_SESSION_NO_LONGER_VALID = 4006
local CLOSE_SESSION_TIMEOUT = 4009
local CLOSE_SERVER_NOT_FOUND = 4011
local CLOSE_UNKNOWN_PROTOCOL = 4012
local CLOSE_DISCONNECTED = 4014
local CLOSE_VOICE_SERVER_CRASHED = 4015
local CLOSE_UNKNOWN_ENCRYPTION_MODE = 4016
-- Sent when the voice channel/server requires Discord's DAVE (MLS-based
-- E2EE) protocol and the client's IDENTIFY did not offer it (this
-- library always sends max_dave_protocol_version = 0, see
-- VoiceGateway:identify, since it does not implement the DAVE MLS key
-- exchange). Not resumable and not worth retrying: every retry will
-- IDENTIFY with the same max_dave_protocol_version = 0 and get the
-- same 4017 again, forever, until DAVE support is actually added.
local CLOSE_DAVE_PROTOCOL_REQUIRED = 4017

-- Close codes after which Discord explicitly says resuming is safe.
local RESUMABLE_CLOSE_CODES = {
    [CLOSE_VOICE_SERVER_CRASHED] = true,
}

-- Close codes that mean the session itself is invalid, so a RESUME
-- would just fail again; a fresh IDENTIFY (new session_id from a new
-- voice_state_update) is required instead.
local SESSION_INVALID_CLOSE_CODES = {
    [CLOSE_SESSION_NO_LONGER_VALID] = true,
    [CLOSE_SESSION_TIMEOUT] = true,
}

-- Close codes after which reconnecting at all is pointless (the bot was
-- kicked, the channel/guild is gone, or the main gateway session that
-- backs this voice session was dropped).
local FATAL_CLOSE_CODES = {
    [CLOSE_DISCONNECTED] = true,
    [CLOSE_DAVE_PROTOCOL_REQUIRED] = true,
}

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

    -- DAVE (E2EE) opcodes
    DAVE_PREPARE_TRANSITION = DAVE_PREPARE_TRANSITION,
    DAVE_EXECUTE_TRANSITION = DAVE_EXECUTE_TRANSITION,
    DAVE_TRANSITION_READY = DAVE_TRANSITION_READY,
    DAVE_PREPARE_EPOCH = DAVE_PREPARE_EPOCH,
    MLS_EXTERNAL_SENDER_PACKAGE = MLS_EXTERNAL_SENDER_PACKAGE,
    MLS_KEY_PACKAGE = MLS_KEY_PACKAGE,
    MLS_PROPOSALS = MLS_PROPOSALS,
    MLS_COMMIT_WELCOME = MLS_COMMIT_WELCOME,
    MLS_COMMIT_TRANSITION = MLS_COMMIT_TRANSITION,
    MLS_WELCOME = MLS_WELCOME,
    MLS_INVALID_COMMIT_WELCOME = MLS_INVALID_COMMIT_WELCOME,

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

    -- Close codes
    CLOSE_UNKNOWN_OPCODE = CLOSE_UNKNOWN_OPCODE,
    CLOSE_FAILED_TO_DECODE = CLOSE_FAILED_TO_DECODE,
    CLOSE_NOT_AUTHENTICATED = CLOSE_NOT_AUTHENTICATED,
    CLOSE_AUTHENTICATION_FAILED = CLOSE_AUTHENTICATION_FAILED,
    CLOSE_ALREADY_AUTHENTICATED = CLOSE_ALREADY_AUTHENTICATED,
    CLOSE_SESSION_NO_LONGER_VALID = CLOSE_SESSION_NO_LONGER_VALID,
    CLOSE_SESSION_TIMEOUT = CLOSE_SESSION_TIMEOUT,
    CLOSE_SERVER_NOT_FOUND = CLOSE_SERVER_NOT_FOUND,
    CLOSE_UNKNOWN_PROTOCOL = CLOSE_UNKNOWN_PROTOCOL,
    CLOSE_DISCONNECTED = CLOSE_DISCONNECTED,
    CLOSE_VOICE_SERVER_CRASHED = CLOSE_VOICE_SERVER_CRASHED,
    CLOSE_UNKNOWN_ENCRYPTION_MODE = CLOSE_UNKNOWN_ENCRYPTION_MODE,
    CLOSE_DAVE_PROTOCOL_REQUIRED = CLOSE_DAVE_PROTOCOL_REQUIRED,
    RESUMABLE_CLOSE_CODES = RESUMABLE_CLOSE_CODES,
    SESSION_INVALID_CLOSE_CODES = SESSION_INVALID_CLOSE_CODES,
    FATAL_CLOSE_CODES = FATAL_CLOSE_CODES,
}

return M
