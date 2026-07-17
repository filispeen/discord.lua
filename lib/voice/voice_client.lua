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

local class = require("core.class")
local emitter = require("core.emitter")
local enums = require("voice.enums")
local errors = require("voice.errors")
local opus = require("voice.opus")
local udp = require("voice.udp")
local VoiceGateway = require("voice.voice_gateway")

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
        },
        gateway = nil,
        udp = nil,
        _timer = nil,
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

    -- Create UDP client
    self.udp = udp.UDPClient:new(nil, nil)

    -- Create gateway
    self.gateway = VoiceGateway.new(self.client, self.guild.id)
    self.gateway._voice_client = self

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
end

-- Connect to voice channel
function VoiceClient:connect()
    local state = self.state

    -- Check if already connected
    if state.connected then
        return true
    end

    -- Set guild voice state
    -- self.client:voice_state_update({
    --     guild_id = self.guild.id,
    --     channel_id = self.channel.id,
    --     self_mute = false,
    --     self_deaf = false,
    -- })

    -- Get voice server endpoint
    -- This would come from the gateway
    -- For now, mock it
    self.state.endpoint = "wss://example.com"  -- TODO: Get from guild

    -- Identify to voice gateway
    local success, err = self.gateway:identify()
    if not success then
        return false, err
    end

    return true
end

-- Disconnect from voice
function VoiceClient:disconnect(force)
    local state = self.state

    if force then
        -- Force disconnect - stop playing, close everything
        if self._timer then
            luv.timer:stop(self._timer)
            self._timer = nil
        end

        if self.udp and self.udp.close then
            self.udp:close()
        end

        if self.gateway and self.gateway.close then
            self.gateway:close()
        end
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
        luv.timer:stop(self._timer)
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
            luv.timer:stop(self._timer)
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
        luv.timer:stop(self._timer)
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

-- Internal: on ready event
function VoiceClient:_on_ready(data)
    local state = self.state
    state.ssrc = data.ssrc
    state.ip = data.ip
    state.port = data.port
    state.modes = data.modes
    state.heartbeat_interval = data.heartbeat_interval
    state.connected = true

    -- Connect UDP
    if self.udp then
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
