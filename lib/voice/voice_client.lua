-- lib/voice/voice_client.lua
-- Voice client - main API for connecting to voice channels
--
-- Public Contract:
--   VoiceClient:new(client, channel) - Create client
--   client:connect() - Connect to voice channel
--   client:disconnect(force?) - Disconnect from voice
--   client:move_to(channel) - Move to different voice channel
--   client:is_connected() - Check if connected
--   client:is_playing() - Check if playing audio
--   client:play(source, options) - Play audio source
--   client:stop() - Stop playing
--   client:pause() - Pause playback
--   client:resume() - Resume playback
--   client:elapsed() - Get elapsed playback time
--   client:send_audio_packet(data, encode?) - Send raw audio packet
--
--   client:start_recording(sink, finished_callback, ...) -> boolean, string?
--     sink: a Sink instance (see lib/voice/sinks/), e.g. WaveSink.new()
--     finished_callback: function(sink, ...) called from stop_recording
--     ...: extra arguments forwarded to finished_callback, mirrors pycord's
--     vc.start_recording(sink, callback, ctx.channel).
--     Sets sink.vc = self so finished_callback can call sink.vc:disconnect().
--     See lib/voice/sinks/sink.lua for the RTP-receive-pipeline limitation:
--     this starts bookkeeping and calls sink:write() for any audio pushed
--     through client:_feed_recording(user_id, data), but there is no
--     automatic RTP decode loop yet feeding real call audio into it.
--
--   client:stop_recording() -> boolean, string?
--     Calls sink:cleanup() then the finished_callback with (sink, ...).

local class = require("core.class")
local emitter = require("core.emitter")
local enums = require("voice.enums")
local errors = require("voice.errors")
local opus = require("voice.opus")
local udp = require("voice.udp")
local VoiceGateway = require("voice.voice_gateway")
local luv = require("core.luv_compat")

local VoiceClient = class("VoiceClient")
function VoiceClient.new(client, channel)
    local self = {
        client = client,
        channel = channel,
        guild = channel.guild,
        user = client.user,
        state = {
            connected = false,
            playing = false,
            paused = false,
            elapsed = 0,
            source = nil,
            session_id = nil,
            token = nil,
            endpoint = nil,
            ssrc = nil,
            mode = "xsalsa20_poly1305_suffix",
            secret_key = nil,
            encoder = nil,
            decoder = nil,
            packets = {},
            ssrc_map = {},
            known_users = {},
        },
        gateway = nil,
        udp = nil,
        _timer = nil,
        _recording = nil,
    }
    setmetatable(self, VoiceClient)
    self:setup()
    return self
end

-- Setup voice client
function VoiceClient:setup()
    local state = self.state

    -- Create Opus encoder
    state.encoder = opus.Encoder:new({
        application = "lowdelay",
        bitrate = 128,
        fec = true,
        expected_packet_loss = 0.15,
        bandwidth = "full",
        signal_type = "auto",
    })

    -- Create Opus decoder
    state.decoder = opus.Decoder:new()

    -- Create UDP client (endpoint is set once we learn the voice server's
    -- ip/port from the gateway READY event, see _on_ready below)
    self.udp = udp.UDPClient:new(nil, nil)

    -- Create gateway
    self.gateway = VoiceGateway.new(self.client, self.guild.id)
    self.gateway._voice_client = self

    -- Track VOICE_STATE_UPDATE/VOICE_SERVER_UPDATE dispatches from the
    -- main gateway (see Client:start_gateway). Discord sends both after
    -- Shard:voice_state_update(); once we have all three of session_id,
    -- token and endpoint we open the voice WebSocket.
    -- Stored on self so disconnect(true) can unsubscribe them: self.client
    -- is the shared main-gateway Client, so leaving these attached after
    -- disconnect would leak a listener that keeps reacting to every future
    -- voice_state_update/voice_server_update on this client, including
    -- ones meant for a brand new VoiceClient created by a later connect.
    self._on_voice_state_update = function(data)
        if data.guild_id ~= self.guild.id or data.user_id ~= self.user.id then
            return
        end
        state.session_id = data.session_id
        self:_maybe_connect_gateway()
    end
    self.client:on('voice_state_update', self._on_voice_state_update)

    self._on_voice_server_update = function(data)
        if data.guild_id ~= self.guild.id then
            return
        end
        state.token = data.token
        state.endpoint = data.endpoint
        self:_maybe_connect_gateway()
    end
    self.client:on('voice_server_update', self._on_voice_server_update)

    -- Add listeners
    self.gateway:on('ready', function(data)
        self:_on_ready(data)
    end)

    self.gateway:on('client_connect', function(data)
        self:_on_client_connect(data)
    end)

    self.gateway:on('client_disconnect', function(data)
        self:_on_client_disconnect(data)
    end)

    self.gateway:on('speaking', function(data)
        self:_on_speaking(data)
    end)

    -- Session-invalid close code (4006/4009): the gateway already cleared
    -- session_id/token/seq on its side since RESUME would fail against a
    -- dead session. Clear our copy of session_id too so a later
    -- voice_state_update reply is treated as fresh, then re-request a
    -- new session the same way connect() does.
    self.gateway:on('session_invalidated', function(data)
        state.session_id = nil
        self.client:voice_state_update(self.guild.id, self.channel.id, false, false)
        self.client:dispatch('VOICE_CLIENT_SESSION_INVALIDATED', data)
    end)

    -- Fatal close code or backoff attempts exhausted: the gateway has
    -- given up on its own, no automatic reconnect will happen. Mark
    -- ourselves disconnected and let the bot author decide whether to
    -- call connect() again.
    self.gateway:on('reconnect_failed', function(data)
        state.connected = false
        self.client:dispatch('VOICE_CLIENT_RECONNECT_FAILED', data)
    end)

    -- Session description carries the secret_key used to encrypt/decrypt
    -- RTP payloads over UDP. Store it on state and hand it to the UDP
    -- client so incoming packets can be decrypted (see udp.lua's
    -- _decode_packet, which reads udp._state.secret_key).
    self.gateway:on('session_description', function(data)
        state.secret_key = data.secret_key
        state.mode = data.mode
        if self.udp then
            self.udp._state.secret_key = data.secret_key
            self.udp._state.mode = data.mode
        end
    end)

    -- Routes decrypted RTP payloads from the UDP client into the active
    -- recording sink, keyed by SSRC->user_id (populated by
    -- _on_client_connect from the gateway's client_connect event). Packets
    -- from an SSRC with no known user_id yet are dropped; this can happen
    -- for a brief window right after a user starts speaking if the
    -- gateway's client_connect/speaking events arrive after their first
    -- RTP packets. self.udp._state.on_packet is udp.lua's real dispatch
    -- hook (see UDPClient:_dispatch_packet).
    self.udp._state.on_packet = function(rtp_header, payload)
        local user_id = state.ssrc_map[rtp_header.ssrc]
        if not user_id then
            return
        end
        self:_feed_recording(user_id, payload)
    end
end

-- Connect to voice channel. Sends VOICE_STATE_UPDATE through the main
-- gateway; the actual voice WebSocket connect happens once Discord
-- replies with VOICE_STATE_UPDATE + VOICE_SERVER_UPDATE, handled by
-- _maybe_connect_gateway (registered in setup()).
function VoiceClient:connect()
    local state = self.state

    -- Check if already connected
    if state.connected then
        return true
    end

    self.client:voice_state_update(self.guild.id, self.channel.id, false, false)

    return true
end

-- Internal: called after either VOICE_STATE_UPDATE or VOICE_SERVER_UPDATE
-- arrives for this guild. Opens the voice WebSocket once we have all
-- three of session_id, token and endpoint.
function VoiceClient:_maybe_connect_gateway()
    local state = self.state
    if not (state.session_id and state.token and state.endpoint) then
        return
    end
    self.gateway:connect(state.endpoint, state.token, state.session_id)
end

-- Disconnect from voice
function VoiceClient:disconnect(force)
    local state = self.state

    if force then
        -- Force disconnect - stop playing, close everything
        if self._timer then
            self._timer:stop()
            self._timer = nil
        end

        if self.udp and self.udp.close then
            self.udp:close()
        end

        if self.gateway and self.gateway.close then
            self.gateway:close()
        end

        self.client:off('voice_state_update', self._on_voice_state_update)
        self.client:off('voice_server_update', self._on_voice_server_update)

        self.client:voice_state_update(self.guild.id, nil, false, false)
    else
        -- Graceful disconnect
        if self.state.playing then
            self:stop()
        end
    end

    state.connected = false
    state.playing = false
    state.source = nil

    return true
end

-- Move to different voice channel
function VoiceClient:move_to(channel)
    local state = self.state

    if not state.connected then
        error("Not connected", 0)
    end

    -- self.client:voice_state_update({
    --     guild_id = self.guild.id,
    --     channel_id = channel.id,
    --     self_mute = state.mute,
    --     self_deaf = false,
    -- })

    self.channel = channel

    return true
end

-- Check if connected
function VoiceClient:is_connected()
    local state = self.state
    return state.connected
end

-- Check if playing
function VoiceClient:is_playing()
    local state = self.state
    return state.playing
end

-- Check if paused
function VoiceClient:is_paused()
    local state = self.state
    return state.paused
end

-- Play audio source
function VoiceClient:play(source, options)
    local state = self.state

    if not state.connected then
        return false, "Not connected"
    end

    state.source = source
    state.playing = true
    state.paused = false

    -- Start playback timer
    self:_start_playback()

    -- Start processing source
    self:_process_source(source, options)

    return true
end

-- Stop playing
function VoiceClient:stop()
    local state = self.state

    if self._timer then
        self._timer:stop()
        self._timer = nil
    end

    state.playing = false
    state.source = nil

    return true
end

-- Pause playback
function VoiceClient:pause()
    local state = self.state

    if state.playing then
        state.paused = true
        if self._timer then
            self._timer:stop()
        end
    end

    return true
end

-- Resume playback
function VoiceClient:resume()
    local state = self.state

    if state.paused and state.source then
        state.paused = false
        self:_start_playback()
    end

    return true
end

-- Get elapsed playback time
function VoiceClient:elapsed()
    local state = self.state
    return state.elapsed
end

-- Send audio packet
function VoiceClient:send_audio_packet(data, encode)
    local state = self.state

    if encode then
        -- Encode PCM to Opus
        if not state.encoder then
            return false, "Encoder not initialized"
        end

        local success, err = pcall(function()
            return state.encoder:encode(data)
        end)

        if not success then
            return false, err
        end

        local opus_packet, size = success and { data[1], data[2] } or nil

        if not opus_packet then
            return false, "Encoding failed"
        end

        -- Send via UDP
        if not self.udp then
            return false, "UDP not connected"
        end

        local success, err = self.udp:send(opus_packet)
        if not success then
            return false, err
        end
    else
        -- Send raw packet
        if not self.udp then
            return false, "UDP not connected"
        end

        local success, err = self.udp:send(data)
        if not success then
            return false, err
        end
    end

    return true
end

-- Start playback timer
function VoiceClient:_start_playback()
    local state = self.state
    local source = state.source

    if not source then
        return
    end

    if self._timer then
        self._timer:stop()
    end

    -- Frame timing: 20ms Opus frames
    local frame_interval = 20  -- milliseconds

    self._timer = luv.timer:new()
    self._timer:start(0, frame_interval, function()
        if not source:is_playing() then
            return
        end

        -- Read next frame from source
        local chunk = source:read()
        if not chunk then
            -- Source finished, stop playback
            self:stop()
            return
        end

        -- Encode and send
        self:send_audio_packet(chunk, true)

        -- Continue loop
        if not source:is_playing() then
            self:stop()
        end
    end)
end

-- Process audio source
function VoiceClient:_process_source(source, options)
    local state = self.state

    -- Read initial data
    local chunk = source:read()
    if not chunk then
        return
    end

    -- Encode and send
    self:send_audio_packet(chunk, true)

    -- Continue reading
    -- This would be handled by the playback timer
end

-- Starts recording with the given sink, mirrors pycord's
-- vc.start_recording(sink, callback, *args). See this file's module
-- header for the RTP-receive-pipeline limitation: recording state is
-- tracked and sink:write() is available via _feed_recording, but nothing
-- calls it automatically yet without a real RTP decode loop.
function VoiceClient:start_recording(sink, finished_callback, ...)
    if not self.state.connected then
        return false, "Not connected"
    end
    if self._recording then
        return false, "Already recording"
    end

    sink.vc = self

    self._recording = {
        sink = sink,
        finished_callback = finished_callback,
        args = { ... },
    }

    return true
end

-- Feeds one Opus RTP payload for user_id into the active recording sink,
-- the manual entry point described in start_recording's doc comment
-- until a real RTP receive loop exists to call this automatically.
function VoiceClient:_feed_recording(user_id, opus_data)
    if not self._recording then
        return false, "Not recording"
    end
    self._recording.sink:write(user_id, opus_data)
    return true
end

-- Stops recording, finalizes the sink, and invokes finished_callback,
-- mirrors pycord's vc.stop_recording().
function VoiceClient:stop_recording()
    if not self._recording then
        return false, "Not recording"
    end

    local recording = self._recording
    self._recording = nil

    recording.sink:cleanup()

    if recording.finished_callback then
        recording.finished_callback(recording.sink, table.unpack(recording.args))
    end

    return true
end

-- Internal: on ready event
function VoiceClient:_on_ready(data)
    local state = self.state
    state.ssrc = data.ssrc
    state.ip = data.ip
    state.port = data.port
    state.modes = data.modes
    state.heartbeat_interval = data.heartbeat_interval
    state.connected = true

    -- Connect UDP now that we know the voice server's ip/port
    if self.udp then
        self.udp._state.endpoint = data.ip .. ":" .. tostring(data.port)
        self.udp:connect()
    end

    -- Send session description
    if self.gateway then
        self.gateway:send_session_description()
    end

    -- Dispatch connected event
    self.client:dispatch('VOICE_CLIENT_CONNECTED', self)

    return true
end

-- Internal: on client connect
function VoiceClient:_on_client_connect(data)
    local state = self.state
    state.known_users[data.user_id] = data
    state.ssrc_map[data.ssrc] = data.user_id

    -- Dispatch event
    self.client:dispatch('VOICE_CLIENT_CONNECT', {
        user_id = data.user_id,
        ssrc = data.ssrc,
    })

    return true
end

-- Internal: on client disconnect
function VoiceClient:_on_client_disconnect(data)
    local state = self.state
    state.known_users[data.user_id] = nil
    state.ssrc_map[data.ssrc] = nil

    -- Dispatch event
    self.client:dispatch('VOICE_CLIENT_DISCONNECT', {
        user_id = data.user_id,
        ssrc = data.ssrc,
    })

    return true
end

-- Internal: on speaking update
function VoiceClient:_on_speaking(data)
    -- Dispatch event
    self.client:dispatch('VOICE_SPEAKING', {
        user_id = data.user_id,
        ssrc = data.ssrc,
        speaking = data.speaking,
    })

    return true
end

return VoiceClient
