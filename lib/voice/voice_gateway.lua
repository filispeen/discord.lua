-- lib/voice/voice_gateway.lua
-- Voice gateway WebSocket connection
--
-- Public Contract:
--   VoiceGateway:new(client, guild_id) - Create gateway
--   gateway:connect(endpoint, token, session_id) - Open the voice
--     WebSocket and route incoming frames to receive_hello/receive_ready/
--     receive_session_description and the client_connect/client_disconnect/
--     speaking/resumed events. endpoint is the raw host (no scheme/port)
--     as sent in VOICE_SERVER_UPDATE, e.g. "guildvoice.discord.gg".
--   gateway:identify() - Send identify payload
--   gateway:send_heartbeat() - Send heartbeat
--   gateway:send_session_description() - Send encrypted session key
--   gateway:resume(session_id, seq) - Resume connection
--   gateway:receive_hello() - Handle HELLO event
--   gateway:receive_ready() - Handle READY event
--   gateway:receive_session_description(data) - Handle SESSION_DESCRIPTION, sets secret_key
--   gateway:send_client_connect(user_id, ssrc) - Client connected
--   gateway:send_client_disconnect(user_id, ssrc) - Client disconnected
--   gateway:send_speaking(user_id, ssrc, speaking) - Speaking update
--   gateway:on(event, callback) - Subscribe to a gateway event
--   gateway:off(event, callback?) - Unsubscribe from a gateway event
--   gateway:emit(event, ...) - Emit a gateway event to subscribers

local class = require("core.class")
local enums = require("voice.enums")
local errors = require("voice.errors")

local VoiceGateway = class("VoiceGateway")

function VoiceGateway.new(client, guild_id)
    local self = {
        client = client,
        guild_id = guild_id,
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

    local host = endpoint:match("^([^:]+)")
    local url = "wss://" .. host .. "/?v=8"

    local ws = require("coro-websocket").connect(url)
    self.ws = ws

    ws:on("open", function()
        state.connected = true
        self:identify()
    end)

    ws:on("message", function(msg)
        local json = require("dkjson")
        local ok, parsed = pcall(json.decode, msg)
        if not ok or type(parsed) ~= "table" then
            return
        end
        self:_dispatch(parsed)
    end)

    ws:on("close", function(code, reason)
        state.connected = false
        self:emit("close", { code = code, reason = reason })
    end)

    ws:on("error", function(err)
        self:emit("error", errors.VoiceConnectError.new("WebSocket error: " .. tostring(err)))
    end)

    return self
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
        self:emit("resumed", data)
    elseif op == enums.CLIENT_CONNECT or op == enums.CLIENTS_CONNECT then
        self:emit("client_connect", data)
    elseif op == enums.CLIENT_DISCONNECT then
        self:emit("client_disconnect", data)
    elseif op == enums.SPEAKING then
        self:emit("speaking", data)
    end
end

function VoiceGateway:identify()
    local payload = {
        op = enums.IDENTIFY,
        d = {
            user_id = self.client.user.id,
            server_id = self.guild_id,
            session_id = self.state.session_id,
            token = self.state.token,
            shard = 0,  -- TODO: get from client
            total_shards = 1,
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
            seq_ack = state.seq,
        },
    }

    state.last_heartbeat = os.time() * 1000

    return self:_send(payload)
end

-- Send session description (encrypted)
function VoiceGateway:send_session_description()
    local payload = {
        op = enums.SESSION_DESCRIPTION,
        d = {
            mode = enums.SUPPORTED_MODES[1],  -- xsalsa20_poly1305_suffix
            secret = self.secret_key,
        },
    }

    return self:_send(payload)
end

-- Receive SESSION_DESCRIPTION event from the server. This is the server's
-- reply after we SELECT_PROTOCOL; it carries the secret_key used to
-- encrypt/decrypt RTP payloads (see lib/voice/crypto.lua). Routed here by
-- VoiceGateway:_dispatch when a live connect() socket is active.
function VoiceGateway:receive_session_description(data)
    self.secret_key = data.secret_key
    self.mode = data.mode

    self:emit("session_description", {
        secret_key = data.secret_key,
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

-- Send heartbeat
function VoiceGateway:_send_heartbeat()
    local state = self.state
    local payload = {
        op = enums.HEARTBEAT,
        d = {
            t = os.time() * 1000,
            seq_ack = state.seq,
        },
    }

    state.last_heartbeat = os.time() * 1000
    return self:_send(payload)
end

-- Send payload to WebSocket
function VoiceGateway:_send(payload)
    local ws = self.ws

    if not ws then
        return false, "WebSocket not connected"
    end

    local json = require("dkjson")
    local data = {
        op = payload.op,
        d = payload.d,
    }

    ws:send(json.encode(data))
    return true
end

-- Receive HELLO event
function VoiceGateway:receive_hello(data)
    local state = self.state

    state.heartbeat_interval = data.heartbeat_interval
    state.ssrc = data.ssrc
    state.ip = data.ip
    state.port = data.port
    state.modes = data.modes

    -- Start heartbeat timer
    self:_start_heartbeat()

    -- Dispatch ready event
    self:_dispatch_ready({
        ssrc = data.ssrc,
        ip = data.ip,
        port = data.port,
        modes = data.modes,
        heartbeat_interval = data.heartbeat_interval,
    })

    return true
end

-- Receive READY event
function VoiceGateway:receive_ready(data)
    local state = self.state
    state.seq = data.seq

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

    if self._heartbeat_timer then
        self:_stop_heartbeat()
    end

    local heartbeat_timer = {
        interval = interval,
        started = true,
    }

    state.heartbeat_timer = heartbeat_timer
end

-- Stop heartbeat timer
function VoiceGateway:_stop_heartbeat()
    if self._heartbeat_timer then
        self._heartbeat_timer = nil
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

-- Send speaking update
function VoiceGateway:send_speaking(user_id, ssrc, speaking)
    local payload = {
        op = enums.SPEAKING,
        d = {
            user_id = user_id,
            ssrc = ssrc,
            speaking = speaking,
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
    if latency > 2000 then  -- 2 second threshold
        -- High latency, could trigger reconnect
        -- self:_trigger_reconnect()
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

-- Trigger reconnect
function VoiceGateway:_trigger_reconnect()
    -- Stop heartbeat timer
    self:_stop_heartbeat()

    -- Reset state
    self.state = {
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
    }

    -- Dispatch reconnect event
    -- self.client:dispatch('VOICE_RECONNECT', nil)
end

-- Close connection
function VoiceGateway:close()
    self:_stop_heartbeat()

    if self.ws then
        self.ws:close()
        self.ws = nil
    end

    self.state.connected = false
    return true
end

return VoiceGateway
