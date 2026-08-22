-- lib/voice/voice_gateway.lua
-- Voice gateway WebSocket connection
--
-- Public Contract:
--   VoiceGateway:new(client, guild_id) - Create gateway
--   gateway:connect(endpoint, token, session_id) - Open the voice
--     WebSocket and route incoming frames to receive_hello/receive_ready/
--     receive_session_description and the client_connect/clients_connect/
--     client_disconnect/speaking/resumed events. endpoint is the raw host
--     (no scheme/port) as sent in VOICE_SERVER_UPDATE, e.g.
--     "guildvoice.discord.gg".
--   gateway:identify() - Send identify payload
--   gateway:send_heartbeat() - Send heartbeat
--   gateway:select_protocol(address, port) - Send SELECT_PROTOCOL (op 1)
--     with the externally-discovered UDP address/port; must be called
--     from within a coroutine (see udp.lua's discover_ip). Triggers the
--     server's SESSION_DESCRIPTION (op 4) reply.
--   gateway:resume(session_id, seq) - Resume connection
--   gateway:receive_hello() - Handle HELLO event (heartbeat_interval only,
--     starts the heartbeat timer; does not emit "ready", that only
--     happens once the real READY payload arrives)
--   gateway:receive_ready() - Handle READY event (ssrc/ip/port/modes,
--     emits "ready" via _dispatch_ready)
--   gateway:receive_session_description(data) - Handle SESSION_DESCRIPTION, sets secret_key
--   gateway:send_client_connect(user_id, ssrc) - Client connected
--   gateway:send_client_disconnect(user_id, ssrc) - Client disconnected
--   gateway:send_speaking(speaking) - Announces our own speaking state
--     to the voice gateway (SPEAKING opcode 5). speaking is the
--     SpeakingState bitmask Discord expects: 0 = none, 1 = microphone/
--     voice (what playback should send), 2 = soundshare, 4 = priority.
--     Must be called with speaking=1 before the first RTP audio packet
--     of a talk spurt and speaking=0 once done, or the SFU/receiving
--     clients may not forward/play the audio even though the RTP
--     packets themselves are well-formed and correctly encrypted.
--     Discord's official Speaking payload (docs.discord.food/topics/
--     voice-connections#speaking) requires ssrc alongside speaking and
--     delay: {"op": 5, "d": {"speaking": 5, "delay": 0, "ssrc": 1}} --
--     ssrc is this connection's own SSRC from Ready (state.ssrc), not
--     omitted the way an early reading of pycord's speak() helper
--     might suggest.
--   "client_connect" event - legacy singular opcode (12), data has
--     user_id/audio_ssrc for one client.
--   "clients_connect" event - DAVE opcode (11), data has
--     user_ids = {snowflake, ...}, a plural list with no ssrc. Per the
--     DAVE whitepaper this just tells the client which user IDs are now
--     expected media session members (used to validate MLS add
--     proposals); it carries no per-user ssrc, unlike client_connect.
--   gateway:on(event, callback) - Subscribe to a gateway event
--   gateway:off(event, callback?) - Unsubscribe from a gateway event
--   gateway:emit(event, ...) - Emit a gateway event to subscribers
--
--   Automatic reconnect on an unexpected WebSocket close (not triggered
--   by an explicit gateway:close(), and not for close code 1000):
--     - fatal close codes (see voice.enums.FATAL_CLOSE_CODES, e.g. 4014
--       "Disconnected") give up immediately and emit "reconnect_failed"
--     - session-invalid close codes (see voice.enums.SESSION_INVALID_CLOSE_CODES,
--       4006/4009) clear session_id/token/seq and emit "session_invalidated"
--       instead of reconnecting, since resuming a dead session cannot work;
--       the caller must obtain a fresh session_id via a new voice_state_update
--     - anything else reconnects and RESUMEs with exponential backoff,
--       up to MAX_RECONNECT_ATTEMPTS, emitting "reconnecting" per attempt
--       and "reconnect_failed" if attempts are exhausted

local class = require("../core/class")
local enums = require("./enums")
local errors = require("./errors")
local uv = require("../core/luv_compat")
local dave_ffi = require("./dave_ffi")
local DaveSession = require("./dave_session")

local VoiceGateway = class("VoiceGateway")

-- Max automatic reconnect attempts before giving up and emitting
-- "reconnect_failed" instead of trying again.
local MAX_RECONNECT_ATTEMPTS = 5

-- Base and cap for exponential backoff between reconnect attempts, in
-- milliseconds. attempt 1 waits ~BASE_DELAY_MS, attempt 2 ~2x, etc,
-- capped at MAX_DELAY_MS.
local BASE_DELAY_MS = 1000
local MAX_DELAY_MS = 30000

function VoiceGateway.new(client, guild_id, channel_id)
    local self = {
        client = client,
        guild_id = guild_id,
        channel_id = channel_id,
        ws = nil,
        state = {
            connected = false,
            session_id = nil,
            token = nil,
            ssrc = nil,
            ip = nil,
            port = nil,
            heartbeat_interval = nil,
            last_heartbeat = 0,
            last_ack = 0,
            missed_acks = 0,
            seq = 0,
            state = enums.DISCONNECTED,
        },
        secret_key = nil,
        heartbeat_timer = nil,
        known_users = {},
        listeners = {},
        reconnect_attempts = 0,
        reconnect_timer = nil,
        -- DAVE (E2EE) state. dave_session stays nil for the whole
        -- connection lifetime when libdave is unavailable (see
        -- dave_ffi.available below); every dave_* method in this file
        -- guards on self.dave_session being non-nil first.
        dave_session = nil,
        dave_protocol_version = 0,
        dave_pending_transition = nil,
    }
    setmetatable(self, VoiceGateway)
    return self
end

-- Subscribe to a gateway event
function VoiceGateway:on(event, callback)
    if not self.listeners[event] then
        self.listeners[event] = {}
    end
    table.insert(self.listeners[event], callback)
    return self
end

-- Unsubscribe from a gateway event
function VoiceGateway:off(event, callback)
    if not self.listeners[event] then
        return self
    end
    if not callback then
        self.listeners[event] = nil
    else
        for i, cb in ipairs(self.listeners[event]) do
            if cb == callback then
                table.remove(self.listeners[event], i)
                break
            end
        end
    end
    return self
end

-- Emit a gateway event to all subscribers
function VoiceGateway:emit(event, ...)
    if self.listeners[event] then
        for _, callback in ipairs(self.listeners[event]) do
            callback(...)
        end
    end
    return self
end

-- Open the voice WebSocket and wire incoming frames to this module's
-- receive_* handlers and the client_connect/client_disconnect/speaking/
-- resumed events. endpoint is the raw host from VOICE_SERVER_UPDATE
-- (no scheme, may include a stray ":port" that Discord sometimes sends,
-- which is stripped since the voice gateway always uses wss on 443).
function VoiceGateway:connect(endpoint, token, session_id)
    local state = self.state
    state.token = token
    state.session_id = session_id
    state.endpoint = endpoint
    self._closing = false

    local host, port = endpoint:match("^([^:]+):?(%d*)$")
    local url
    if port and port ~= "" then
        url = "wss://" .. host .. ":" .. port .. "/?v=8"
    else
        url = "wss://" .. host .. "/?v=8"
    end

    -- Mirrors gateway.Shard:connect(): coro-websocket.connect() needs a
    -- parsed options table (host/port/path/tls), not a raw URL string,
    -- and returns the low-level (res, read, write) coroutine contract
    -- rather than an EventEmitter-style object. ws_adapter.wrap gives
    -- this the same :on/:send/:close surface the rest of this function
    -- (and VoiceGateway:_send/:close elsewhere in this file) expects.
    local websocket = require("coro-websocket")
    local utils = require("../utils")
    local ws_adapter = require("../gateway/ws_adapter")

    local options, parse_err = utils.parseUrl(url)
    if not options then
        self:emit("error", errors.VoiceConnectError.new("Failed to parse voice endpoint: " .. tostring(parse_err)))
        return self
    end

    local res, read, write = websocket.connect(options)
    if not res then
        self:emit("error", errors.VoiceConnectError.new("Failed to connect to voice endpoint: " .. tostring(read)))
        return self
    end

    local ws = ws_adapter.wrap(res, read, write)
    self.ws = ws

    -- core.emitter passes the emitter instance itself as the first
    -- callback argument, so the actual payload is the second argument
    -- here (matching gateway.Shard's ws:on wiring).
    ws:on("open", function()
        state.connected = true
        if self._is_reconnect then
            self:resume(state.session_id, state.seq)
        else
            self:identify()
        end
    end)

    ws:on("message", function(_, msg, is_binary)
        if is_binary then
            self:_dispatch_binary(msg)
            return
        end

        local json = require("../core/json_compat")
        local ok, parsed = pcall(json.decode, msg)
        if not ok or type(parsed) ~= "table" then
            return
        end
        self:_dispatch(parsed)
    end)

    ws:on("close", function(_, code, reason)
        state.connected = false
        self:emit("close", { code = code, reason = reason })
        if not self._closing and code ~= 1000 then
            self:_trigger_reconnect(code, reason)
        end
    end)

    ws:on("error", function(_, err)
        self:emit("error", errors.VoiceConnectError.new("WebSocket error: " .. tostring(err)))
    end)

    ws:start_reading()

    return self
end

-- Builds the recognized_user_ids list DaveSession:process_proposals and
-- :process_welcome expect: every user id announced via clients_connect
-- (11) or client_connect (12) and not since removed by client_disconnect
-- (13). Per the DAVE whitepaper, existing group members must refuse an
-- add proposal for a user id not in this set.
function VoiceGateway:_recognized_user_ids()
    local ids = {}
    for user_id in pairs(self.known_users) do
        ids[#ids + 1] = user_id
    end
    return ids
end

-- Routes a decoded voice gateway payload { op, d, seq } to the matching
-- receive_*/handler based on op, mirroring gateway.Shard:dispatch for the
-- main gateway. Unknown opcodes are ignored.
function VoiceGateway:_dispatch(payload)
    local op = payload.op
    local data = payload.d

    if payload.seq ~= nil then
        self.state.seq = payload.seq
    end

    if op == enums.HELLO then
        self:receive_hello(data)
    elseif op == enums.READY then
        self:receive_ready(data)
    elseif op == enums.SESSION_DESCRIPTION then
        self:receive_session_description(data)
    elseif op == enums.HEARTBEAT_ACK then
        self:_handle_heartbeat_ack()
    elseif op == enums.RESUMED then
        self._is_reconnect = false
        self.reconnect_attempts = 0
        self:emit("resumed", data)
    elseif op == enums.CLIENT_CONNECT then
        if data and data.user_id then
            self.known_users[tostring(data.user_id)] = true
        end
        self:emit("client_connect", data)
    elseif op == enums.CLIENTS_CONNECT then
        if data and data.user_ids then
            for _, user_id in ipairs(data.user_ids) do
                self.known_users[tostring(user_id)] = true
            end
        end
        self:emit("clients_connect", data)
    elseif op == enums.CLIENT_DISCONNECT then
        if data and data.user_id then
            self.known_users[tostring(data.user_id)] = nil
        end
        self:emit("client_disconnect", data)
    elseif op == enums.SPEAKING then
        self:emit("speaking", data)
    elseif self.state.dave_session then
        if op == enums.DAVE_PREPARE_TRANSITION then
            print("DAVE event: DAVE_PREPARE_TRANSITION", "transition_id:", data.transition_id, "protocol_version:", data.protocol_version, "at:", os.date("%H:%M:%S"))
            self:_handle_dave_prepare_transition(data)
        elseif op == enums.DAVE_EXECUTE_TRANSITION then
            print("DAVE event: DAVE_EXECUTE_TRANSITION", "transition_id:", data.transition_id, "at:", os.date("%H:%M:%S"))
            self:_execute_dave_transition(data.transition_id)
        elseif op == enums.DAVE_PREPARE_EPOCH then
            print("DAVE event: DAVE_PREPARE_EPOCH", "epoch:", data.epoch, "protocol_version:", data.protocol_version, "at:", os.date("%H:%M:%S"))
            self:_handle_dave_prepare_epoch(data)
        end
    end
end

-- Mirrors pycord gateway.py's dave_prepare_transition handling: Discord
-- announces an upcoming protocol version change; transition_id == 0
-- applies immediately, otherwise we ack readiness and wait for
-- dave_execute_transition.
function VoiceGateway:_handle_dave_prepare_transition(data)
    local state = self.state
    state.dave_pending_transition = data

    if data.transition_id == 0 then
        self:_execute_dave_transition(data.transition_id)
        return
    end

    if data.protocol_version == 0 and state.dave_session then
        state.dave_session:set_passthrough_mode(true)
    end

    self:send_dave_transition_ready(data.transition_id)
end

-- Mirrors pycord's dave_prepare_epoch handling: epoch == 1 means a brand
-- new MLS group is starting for protocol_version, so the session needs a
-- fresh reinit (equivalent to pycord's state.reinit_dave_session()).
function VoiceGateway:_handle_dave_prepare_epoch(data)
    if data.epoch ~= 1 then
        return
    end

    local state = self.state
    state.dave_protocol_version = data.protocol_version
    self:_reinit_dave_session()
end

-- (Re)creates the MLS group for state.dave_protocol_version and sends
-- our MLS_KEY_PACKAGE, or resets/passthroughs the session when the
-- negotiated version is 0. Mirrors pycord's reinit_dave_session in
-- discord/voice/state.py.
function VoiceGateway:_reinit_dave_session()
    local state = self.state

    if not state.dave_session then
        return
    end

    if state.dave_protocol_version > 0 then
        state.dave_session:reinit(state.dave_protocol_version)

        local key_package = state.dave_session:get_serialized_key_package()
        if key_package then
            self:send_as_bytes(enums.MLS_KEY_PACKAGE, key_package)
        end
    else
        state.dave_session:reset()
        state.dave_session:set_passthrough_mode(true)
    end
end

-- Mirrors pycord's execute_dave_transition: applies a previously
-- prepared transition, tracking up/downgrade so callers (voice_client)
-- can react to is_dave_connection() flipping.
function VoiceGateway:_execute_dave_transition(transition_id)
    local state = self.state
    local pending = state.dave_pending_transition

    if not pending then
        return
    end

    if transition_id == pending.transition_id then
        local old_version = state.dave_protocol_version
        state.dave_protocol_version = pending.protocol_version

        if old_version ~= state.dave_protocol_version and state.dave_protocol_version == 0 then
            self:emit("dave_downgraded", {})
        elseif transition_id > 0 and old_version == 0 and state.dave_protocol_version > 0 then
            if state.dave_session then
                state.dave_session:set_passthrough_mode(false)
            end
            self:emit("dave_upgraded", {})
        end

        if state.dave_session then
            -- refresh_key_ratchet(nil) refreshes our own encryptor
            -- ratchet; refresh_all_known_ratchets fetches and wires up
            -- each peer's OWN decryptor handle onto their new ratchet
            -- (see dave_session.lua's per-user decryptor design) --
            -- there is no shared decryptor state left to invalidate
            -- here, each peer's decryptor is updated in place as part
            -- of that call.
            state.dave_session:refresh_key_ratchet()
            state.dave_session:refresh_all_known_ratchets(self:_recognized_user_ids())

            -- One-shot diagnostic: print the pairwise Voice Privacy
            -- Code for every known peer right after this transition
            -- lands, so it can be read off and compared by hand
            -- against what each peer's official Discord client shows.
            -- Gated on an env var so this never fires unless explicitly
            -- requested. Only latches self._dave_fingerprint_dumped
            -- once an actual peer was found and dumped -- the first
            -- transition after joining an otherwise-empty channel has
            -- no peers yet (recognized_user_ids is just ourselves), so
            -- latching unconditionally here would burn the one-shot on
            -- a transition with nothing to print and silently skip the
            -- later transition where a real peer actually joins.
            if os.getenv("DAVE_DEBUG_FINGERPRINT") and not self._dave_fingerprint_dumped then
                local recognized = self:_recognized_user_ids()
                local dumped_any = false
                for _, user_id in ipairs(recognized) do
                    if tostring(user_id) ~= state.dave_session.user_id then
                        state.dave_session:debug_pairwise_fingerprint_code(user_id)
                        dumped_any = true
                    end
                end
                if dumped_any then
                    self._dave_fingerprint_dumped = true
                end
            end
        end
    end

    state.dave_pending_transition = nil
end

-- Mirrors pycord's recover_dave_from_invalid_commit: tells Discord we
-- failed to process a commit/welcome (MLS_INVALID_COMMIT_WELCOME) and
-- reinitializes our session from scratch so a subsequent welcome can
-- succeed.
function VoiceGateway:_recover_dave_from_invalid_commit(transition_id)
    self:_send({
        op = enums.MLS_INVALID_COMMIT_WELCOME,
        d = { transition_id = transition_id },
    })
    self:_reinit_dave_session()
end

-- Routes a binary voice gateway frame: [seq: u16BE][op: u8][payload...],
-- matching Discord's documented Gateway v8+ wire format for
-- server-to-client MLS_* binary frames. Only MLS_* opcodes (25-31) are
-- ever sent as binary frames.
function VoiceGateway:_dispatch_binary(msg)
    if #msg < 3 then
        return
    end

    local op = msg:byte(3)
    local payload = msg:sub(4)
    local state = self.state

    if not state.dave_session then
        return
    end

    if op == enums.MLS_EXTERNAL_SENDER_PACKAGE then
        print("DAVE event: MLS_EXTERNAL_SENDER_PACKAGE", "at:", os.date("%H:%M:%S"))
        state.dave_session:set_external_sender(payload)
    elseif op == enums.MLS_PROPOSALS then
        if #payload < 1 then
            return
        end
        -- op_byte here is only used to pick "append" vs "revoke" for our
        -- own bookkeeping/logging; it is NOT stripped from the buffer
        -- passed to libdave. Discord's own protocol reference (Voice
        -- Gateway API Reference / opcode summary) documents opcode 27's
        -- payload as the raw add/remove proposals bytes with no leading
        -- Discord-level type byte -- the byte-0 optype reads shown in
        -- some third-party wrappers (e.g. davey's readUInt8(3)+subarray(4))
        -- are that wrapper's own JS-side bookkeeping before calling into
        -- the shared C++ core, not a real wire-format field. Stripping a
        -- byte here previously broke MLS proposal parsing (libdave logged
        -- "Failed to parse MLS proposals: Malformed boolean"), so the
        -- full payload is passed straight through unmodified.
        local op_byte = payload:byte(1)
        local op_type = op_byte == 0 and "append" or "revoke"
        print("DAVE event: MLS_PROPOSALS", "op_type:", op_type, "at:", os.date("%H:%M:%S"))
        local recognized = self:_recognized_user_ids()
        local commit_welcome = state.dave_session:process_proposals(op_type, payload, recognized)
        if commit_welcome then
            self:send_as_bytes(enums.MLS_COMMIT_WELCOME, commit_welcome)
            state.dave_session:refresh_key_ratchet()
            state.dave_session:refresh_all_known_ratchets(recognized)
            state.dave_session:debug_self_loopback_test()
        end
    elseif op == enums.MLS_COMMIT_TRANSITION then
        if #payload < 2 then
            return
        end
        local transition_id = payload:byte(1) * 256 + payload:byte(2)
        print("DAVE event: MLS_COMMIT_TRANSITION", "transition_id:", transition_id, "at:", os.date("%H:%M:%S"))
        local ok = state.dave_session:process_commit(payload:sub(3))
        if ok then
            state.dave_session:refresh_key_ratchet()
            state.dave_session:refresh_all_known_ratchets(self:_recognized_user_ids())
            state.dave_session:debug_self_loopback_test()
            -- Per the DAVE whitepaper (Commit Handling): "Upon successful
            -- processing of the received commit the client... notifies
            -- the voice gateway that they are ready for the associated
            -- transition by sending the dave_protocol_ready_for_transition
            -- opcode (23)." This applies unconditionally, including when
            -- transition_id == 0.
            --
            -- dave_pending_transition must ALSO be set unconditionally
            -- here, including transition_id == 0. _execute_dave_transition
            -- (which handles the server's execute_transition op=22 reply)
            -- no-ops entirely when state.dave_pending_transition is nil.
            -- Previously this was only set for transition_id ~= 0, so for
            -- the very common transition_id == 0 case, an incoming op=22
            -- for transition_id 0 was silently ignored: the decryptor's
            -- pending ratchet was never actually promoted to active, even
            -- though we had already told the gateway we were ready. This
            -- was a root cause of "no valid cryptor found" on every
            -- decrypt following a fresh WELCOME/commit.
            state.dave_pending_transition = {
                transition_id = transition_id,
                protocol_version = state.dave_protocol_version,
            }
            self:send_dave_transition_ready(transition_id)
        else
            self:_recover_dave_from_invalid_commit(transition_id)
        end
    elseif op == enums.MLS_WELCOME then
        if #payload < 2 then
            return
        end
        local transition_id = payload:byte(1) * 256 + payload:byte(2)
        print("DAVE event: MLS_WELCOME", "transition_id:", transition_id, "at:", os.date("%H:%M:%S"))
        local recognized = self:_recognized_user_ids()
        local ok = state.dave_session:process_welcome(payload:sub(3), recognized)
        if ok then
            state.dave_session:refresh_key_ratchet()
            state.dave_session:refresh_all_known_ratchets(recognized)
            state.dave_session:debug_self_loopback_test()
            for _, peer_id in ipairs(recognized) do
                if peer_id ~= state.dave_session.user_id then
                    state.dave_session:debug_pairwise_fingerprint_code(peer_id)
                end
            end
            -- See matching comment above in the MLS_COMMIT_TRANSITION
            -- branch: "Upon successful processing of a dave_mls_welcome
            -- opcode (30) message, welcomed members report that they are
            -- ready for the associated transition by sending the
            -- dave_protocol_ready_for_transition opcode (23)" -- also
            -- unconditional on transition_id, and dave_pending_transition
            -- must be set unconditionally too so a later execute_transition
            -- (op=22) for transition_id 0 is not silently dropped by
            -- _execute_dave_transition's "if not pending then return" guard.
            state.dave_pending_transition = {
                transition_id = transition_id,
                protocol_version = state.dave_protocol_version,
            }
            self:send_dave_transition_ready(transition_id)
        else
            self:_recover_dave_from_invalid_commit(transition_id)
        end
    end
end

-- Sends a binary voice gateway frame: [op: u8] + data, matching pycord's
-- VoiceWebSocket.send_as_bytes. Used for MLS_KEY_PACKAGE,
-- MLS_COMMIT_WELCOME, MLS_INVALID_COMMIT_WELCOME.
function VoiceGateway:send_as_bytes(op, data)
    local ws = self.ws

    if not ws then
        return false, "WebSocket not connected"
    end

    ws:send_bytes(string.char(op) .. data)
    return true
end

-- Sends dave_transition_ready, acking our readiness for a Discord-
-- announced transition_id (JSON opcode 23).
function VoiceGateway:send_dave_transition_ready(transition_id)
    return self:_send({
        op = enums.DAVE_TRANSITION_READY,
        d = { transition_id = transition_id },
    })
end

function VoiceGateway:identify()
    -- DAVE (E2EE) support: max_dave_protocol_version is
    -- daveMaxSupportedProtocolVersion() when libdave (dave_ffi.lua) is
    -- available, 0 otherwise. Explicit 0 rather than omitting the field
    -- when unsupported, since Discord's own docs treat both the same
    -- but some voice gateway builds have been seen rejecting IDENTIFY
    -- payloads that omit it entirely.
    local max_dave_version = 0
    if dave_ffi.available() then
        local supported = dave_ffi.max_supported_protocol_version()
        if supported then
            max_dave_version = supported
        end
    end
    local payload = {
        op = enums.IDENTIFY,
        d = {
            user_id = self.client.user.id,
            server_id = self.guild_id,
            session_id = self.state.session_id,
            token = self.state.token,
            shard = 0,  -- TODO: get from client
            total_shards = 1,
            max_dave_protocol_version = max_dave_version,
        },
    }

    -- Send identify
    return self:_send(payload)
end

-- Send heartbeat
function VoiceGateway:send_heartbeat()
    local state = self.state

    if not state.last_heartbeat then
        state.last_heartbeat = 0
    end

    local payload = {
        op = enums.HEARTBEAT,
        d = {
            t = os.time() * 1000,
            seq_ack = state.seq or -1,
        },
    }

    state.last_heartbeat = os.time() * 1000

    return self:_send(payload)
end

-- Send SELECT_PROTOCOL (op 1). This is the client's reply to READY: it
-- tells the voice server which UDP mode/address/port to use, and must
-- be sent before the server will ever send SESSION_DESCRIPTION (op 4)
-- back. address/port are the externally-visible ip/port discovered via
-- UDP IP discovery (see udp.lua's discover_ip, RFC-style STUN-like
-- probe against the voice server), NOT the local bind address.
--
-- Must be called from inside a coroutine: discover_ip() yields while
-- waiting for the discovery response.
function VoiceGateway:select_protocol(address, port)
    local payload = {
        op = enums.SELECT_PROTOCOL,
        d = {
            protocol = "udp",
            data = {
                address = address,
                port = port,
                mode = enums.SUPPORTED_MODES[1],  -- aead_xchacha20_poly1305_rtpsize
            },
        },
    }

    return self:_send(payload)
end

-- Receive SESSION_DESCRIPTION event from the server. This is the server's
-- reply after we SELECT_PROTOCOL; it carries the secret_key used to
-- encrypt/decrypt RTP payloads (see lib/voice/crypto.lua). Routed here by
-- VoiceGateway:_dispatch when a live connect() socket is active.
function VoiceGateway:receive_session_description(data)
    -- Discord sends secret_key as a JSON array of byte values (e.g.
    -- [12, 34, 56, ...]), decoded by json_compat as a Lua table of
    -- numbers, not a byte string. crypto.aead_decrypt/encrypt need a
    -- real byte string (they ffi.cast it straight to unsigned char*),
    -- so pack it here once at receipt time rather than at every
    -- decrypt call.
    local secret_key = data.secret_key
    if type(secret_key) == "table" then
        local bytes = {}
        for i, byte in ipairs(secret_key) do
            bytes[i] = string.char(byte)
        end
        secret_key = table.concat(bytes)
    end

    self.secret_key = secret_key
    self.mode = data.mode

    local state = self.state
    state.dave_protocol_version = data.dave_protocol_version or 0

    -- Lazily create the DaveSession on the first session_description
    -- that negotiates DAVE, mirroring pycord's reinit_dave_session
    -- (dave_session stays nil the whole call for builds without
    -- libdave, or for calls that never upgrade to DAVE).
    if state.dave_protocol_version > 0 and not state.dave_session then
        local session, err = DaveSession.new(self.client.user.id, self.channel_id)
        if session then
            state.dave_session = session
            self.known_users[tostring(self.client.user.id)] = true
        else
            -- libdave unavailable or session creation failed: fall back
            -- to non-DAVE transport encryption. This will only work if
            -- Discord itself allows a passthrough/non-DAVE call; if the
            -- channel mandates DAVE this connection will still get a
            -- 4017 close from Discord's side, same as before dave_ffi
            -- existed (see enums.CLOSE_DAVE_PROTOCOL_REQUIRED).
            self:emit("dave_unavailable", { reason = err })
        end
    end

    if state.dave_session then
        self:_reinit_dave_session()
    end

    self:emit("session_description", {
        secret_key = secret_key,
        mode = data.mode,
    })

    return true
end

-- Resume connection
function VoiceGateway:resume(session_id, seq)
    local state = self.state
    state.session_id = session_id
    state.seq = seq

    local payload = {
        op = enums.RESUME,
        d = {
            token = state.token,
            session_id = session_id,
            seq = seq,
        },
    }

    return self:_send(payload)
end

-- Send payload to WebSocket
function VoiceGateway:_send(payload)
    local ws = self.ws

    if not ws then
        return false, "WebSocket not connected"
    end

    local json = require("../core/json_compat")
    local data = {
        op = payload.op,
        d = payload.d,
    }

    local encoded = json.encode(data)
    ws:send(encoded)
    return true
end

-- Receive HELLO event
-- HELLO (op 8) only ever carries heartbeat_interval on Discord's real
-- voice gateway, unlike the main gateway's HELLO. ssrc/ip/port/modes are
-- not available yet at this point, they only arrive later on READY (op
-- 2); this used to read those fields off the HELLO payload anyway
-- (always nil in practice) and fired "ready" early with incomplete data,
-- which crashed VoiceClient:_on_ready when it tried to concatenate a nil
-- ip into a UDP endpoint string.
function VoiceGateway:receive_hello(data)
    local state = self.state

    state.heartbeat_interval = math.min(data.heartbeat_interval, 5000)

    -- Start heartbeat timer
    self:_start_heartbeat()

    return true
end

-- Receive READY event
function VoiceGateway:receive_ready(data)
    local state = self.state
    state.seq = data.seq

    -- READY carries its own heartbeat_interval (observed 5500ms), distinct
    -- from and much shorter than HELLO's (observed 55000ms). Discord's
    -- real voice gateway expects heartbeats at the READY interval, not
    -- HELLO's; heartbeating only at HELLO's interval leaves the
    -- connection looking dead to the server long before our first
    -- heartbeat goes out, closing with 4020 well before that heartbeat
    -- is even due. Restart the timer here so the correct interval wins.
    if data.heartbeat_interval then
        local capped = math.min(data.heartbeat_interval, 5000)
        if capped ~= state.heartbeat_interval then
            state.heartbeat_interval = capped
            self:_start_heartbeat()
        end
    end

    -- Dispatch ready event
    self:_dispatch_ready({
        ssrc = data.ssrc,
        ip = data.ip,
        port = data.port,
        modes = data.modes,
    })

    return true
end

-- Dispatch ready event
function VoiceGateway:_dispatch_ready(data)
    self:emit("ready", data)
    return data
end

-- Start heartbeat timer
function VoiceGateway:_start_heartbeat()
    local state = self.state
    local interval = state.heartbeat_interval or 5000

    self:_stop_heartbeat()

    local timer = uv.new_timer()
    timer:start(interval, interval, function()
        local co = coroutine.create(function()
            self:send_heartbeat()
        end)
        local ok, err = coroutine.resume(co)
        if not ok then
            self:emit("error", err)
        end
    end)
    state.heartbeat_timer = timer
end

-- Stop heartbeat timer
function VoiceGateway:_stop_heartbeat()
    if self.state.heartbeat_timer then
        self.state.heartbeat_timer:stop()
        self.state.heartbeat_timer = nil
    end
end

-- Send client connect event
function VoiceGateway:send_client_connect(user_id, ssrc)
    local payload = {
        op = enums.CLIENT_CONNECT,
        d = {
            user_id = user_id,
            ssrc = ssrc,
        },
    }

    return self:_send(payload)
end

-- Send client disconnect event
function VoiceGateway:send_client_disconnect(user_id, ssrc)
    local payload = {
        op = enums.CLIENT_DISCONNECT,
        d = {
            user_id = user_id,
            ssrc = ssrc,
        },
    }

    return self:_send(payload)
end

-- Send speaking update. speaking is a SpeakingState bitmask (0 = none,
-- 1 = microphone/voice, 2 = soundshare, 4 = priority), not a boolean.
-- ssrc must be this connection's own SSRC (state.ssrc, from Ready) --
-- Discord's official Speaking payload requires it even for a client
-- announcing its own state:
-- {"op": 5, "d": {"speaking": 5, "delay": 0, "ssrc": 1}}
-- (docs.discord.food/topics/voice-connections#speaking). Earlier code
-- here omitted ssrc based on a misreading of pycord's speak() helper
-- and Discord silently never forwarded/played any audio as a result --
-- no error in either direction, since sending Speaking without ssrc is
-- not itself malformed enough to reject, it just does not identify
-- which connection is speaking.
function VoiceGateway:send_speaking(speaking, ssrc)
    local payload = {
        op = enums.SPEAKING,
        d = {
            speaking = speaking,
            delay = 0,
            ssrc = ssrc,
        },
    }

    return self:_send(payload)
end

-- Handle heartbeat ACK
function VoiceGateway:_handle_heartbeat_ack()
    local state = self.state

    if not state.last_heartbeat then
        return
    end

    local now = os.time() * 1000
    local latency = now - state.last_heartbeat

    state.last_ack = now

    -- Reset missed acks on successful ack
    state.missed_acks = 0

    -- Check if latency is too high
    if latency > 2000 then  -- luacheck: ignore -- 2 second threshold
        -- TODO: high latency reconnect trigger not yet implemented, see PROG.md
    end
end

-- Check for missed heartbeats
function VoiceGateway:_check_missed_acks()
    local state = self.state
    local missed_threshold = 3  -- Number of missed ACKs before reconnect

    if state.missed_acks >= missed_threshold then
        -- Trigger reconnect
        self:_trigger_reconnect()
    end
end

-- Stop any pending backoff timer before reconnecting, retrying again,
-- or giving up, so a stray delayed timer never fires after a newer
-- attempt already started (or after a clean close()/reconnect success).
function VoiceGateway:_cancel_reconnect_timer()
    if self.reconnect_timer then
        self.reconnect_timer:stop()
        self.reconnect_timer = nil
    end
end

-- Trigger reconnect after an unexpected close. close_code is the raw
-- WebSocket close code Discord sent (nil for a non-protocol drop, e.g.
-- a bare network error). Based on close_code this either:
--   1. gives up entirely for a fatal code (kicked/channel deleted/etc,
--      see enums.FATAL_CLOSE_CODES) - emits "reconnect_failed"
--   2. invalidates the session for a session-invalid code (see
--      enums.SESSION_INVALID_CLOSE_CODES) - the old session_id/token
--      can't be resumed, so this clears them and emits
--      "session_invalidated" for the caller (voice_client.lua) to
--      start a brand new voice_state_update handshake; this module
--      does not reconnect on its own in that case since it has no way
--      to obtain a fresh session_id itself
--   3. otherwise (resumable codes like CLOSE_VOICE_SERVER_CRASHED, or
--      no code at all) reconnects and resumes, honoring
--      MAX_RECONNECT_ATTEMPTS with exponential backoff between tries
--
-- Preserves session_id/token/endpoint/seq for the resumable path so
-- the reconnect can RESUME instead of a fresh identify (mirrors
-- gateway.Shard:dispatch's resume-if-session_id pattern for HELLO).
function VoiceGateway:_trigger_reconnect(close_code, close_reason)
    self:_stop_heartbeat()
    self:_cancel_reconnect_timer()

    if close_code and enums.FATAL_CLOSE_CODES[close_code] then
        self.reconnect_attempts = 0
        self:emit("reconnect_failed", {
            reason = "fatal_close_code",
            code = close_code,
            close_reason = close_reason,
        })
        return
    end

    local state = self.state
    local session_id = state.session_id
    local token = state.token
    local endpoint = state.endpoint
    local seq = state.seq
    local session_invalid = close_code and enums.SESSION_INVALID_CLOSE_CODES[close_code]

    if session_invalid then
        session_id = nil
        token = nil
        seq = 0
    end

    -- state.dave_session owns FFI handles (dave_session.lua) that are
    -- not garbage collected automatically; must be destroyed here since
    -- the table below replaces self.state wholesale and would otherwise
    -- leak the handle on every reconnect. A fresh session is created
    -- again lazily on the next session_description (receive_session_description).
    if state.dave_session then
        state.dave_session:destroy()
    end

    self.state = {
        connected = false,
        session_id = session_id,
        token = token,
        endpoint = endpoint,
        ssrc = nil,
        ip = nil,
        port = nil,
        heartbeat_interval = nil,
        last_heartbeat = 0,
        last_ack = 0,
        missed_acks = 0,
        seq = seq,
        state = enums.DISCONNECTED,
        dave_session = nil,
        dave_protocol_version = 0,
        dave_pending_transition = nil,
    }

    -- Explicitly close the dead socket rather than just dropping our
    -- reference to it: leaving the underlying TCP connection open to
    -- the old voice server lets Discord's voice server keep treating
    -- the old session as still live on its side. Observed live: after
    -- a 4006, a fresh voice_state_update (even with an explicit
    -- leave+rejoin) kept getting back the exact same session_id AND
    -- the exact same endpoint, forever, which only makes sense if
    -- Discord's voice server hadn't yet noticed the client was gone.
    if self.ws then
        local old_ws = self.ws
        self.ws = nil
        old_ws:close()
    end

    if session_invalid then
        self._is_reconnect = false
        self.reconnect_attempts = 0
        self:emit("session_invalidated", { code = close_code, close_reason = close_reason })
        return
    end

    self.reconnect_attempts = self.reconnect_attempts + 1

    if self.reconnect_attempts > MAX_RECONNECT_ATTEMPTS then
        self.reconnect_attempts = 0
        self:emit("reconnect_failed", {
            reason = "max_attempts_exceeded",
            code = close_code,
            close_reason = close_reason,
        })
        return
    end

    self:emit("reconnecting", {
        session_id = session_id,
        seq = seq,
        attempt = self.reconnect_attempts,
    })

    if not (endpoint and token and session_id) then
        return
    end

    local delay = math.min(BASE_DELAY_MS * (2 ^ (self.reconnect_attempts - 1)), MAX_DELAY_MS)
    local timer = uv.new_timer()
    self.reconnect_timer = timer
    timer:start(delay, 0, function()
        self.reconnect_timer = nil
        self._is_reconnect = true

        -- connect() opens a new WebSocket via coro-websocket, which
        -- yields internally (coro-net's TCP connect is coroutine-based).
        -- uv timer callbacks run as plain C callbacks, not inside a Lua
        -- coroutine, so a bare self:connect(...) here yields across a
        -- C-call boundary and crashes ("attempt to yield across C-call
        -- boundary", confirmed live). Wrap it in its own coroutine, the
        -- same pattern ws_adapter.lua uses for ws:send/ws:close.
        local co = coroutine.create(function()
            self:connect(endpoint, token, session_id)
        end)
        local ok, err = coroutine.resume(co)
        if not ok then
            self:emit("error", err)
        end
    end)
end

-- Close connection
function VoiceGateway:close()
    self:_stop_heartbeat()
    self:_cancel_reconnect_timer()
    self._closing = true

    if self.ws then
        self.ws:close()
        self.ws = nil
    end

    if self.state.dave_session then
        self.state.dave_session:destroy()
        self.state.dave_session = nil
    end

    self.state.connected = false
    self._is_reconnect = false
    self.reconnect_attempts = 0
    return true
end

return VoiceGateway
