-- lib/voice/voice_gateway.lua
-- Voice gateway WebSocket connection
--
-- Public Contract:
--   VoiceGateway:new(client, guild_id) - Create gateway
--   gateway:identify() - Send identify payload
--   gateway:send_heartbeat() - Send heartbeat
--   gateway:send_session_description() - Send encrypted session key
--   gateway:resume(session_id, seq) - Resume connection
--   gateway:receive_hello() - Handle HELLO event
--   gateway:receive_ready() - Handle READY event
--   gateway:send_client_connect(user_id, ssrc) - Client connected
--   gateway:send_client_disconnect(user_id, ssrc) - Client disconnected
--   gateway:send_speaking(user_id, ssrc, speaking) - Speaking update

local class = require("core.class")
local enums = require("voice.enums")
local errors = require("voice.errors")

local VoiceGateway = class("VoiceGateway")

function VoiceGateway:new(client, guild_id)
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
    }
    setmetatable(self, VoiceGateway)
    return self
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

    local data = {
        op = payload.op,
        d = payload.d,
    }

    ws:send(data)
    return true
end

-- Receive HELLO event
function VoiceGateway:receive_hello(data)
    local state = self.state

    state.heartbeat_interval = data.heartbeat_interval
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
    -- This would dispatch to the client
    -- self.client:dispatch('VOICE_READY', data)
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
        -- self.ws:close()
        self.ws = nil
    end

    self.state.connected = false
    return true
end

local M = {
    VoiceGateway = VoiceGateway,
}

return M
