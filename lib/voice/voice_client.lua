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
--     Incoming RTP audio is routed here automatically: UDPClient's
--     on_packet hook feeds each SSRC's per-user jitter buffer (see
--     opus.PacketDecoder), and a timer (_start_jitter_timer,
--     _flush_jitter_buffers) periodically drains reordered packets into
--     sink:write() via client:_feed_recording(user_id, data).
--     _feed_recording decodes Opus to PCM per user (own libopus decoder
--     instance per SSRC/user, see _get_recording_decoder) before handing
--     data to the sink when libopus/FFI is available; otherwise the raw
--     Opus payload is passed through. See lib/voice/sinks/ for which
--     sinks expect which.
--
--   client:stop_recording() -> boolean, string?
--     Calls sink:cleanup() then the finished_callback with (sink, ...).

local class = require("../core/class")
local opus = require("./opus")
local udp = require("./udp")
local VoiceGateway = require("./voice_gateway")
local luv = require("../core/luv_compat")

-- Backoff for the leave+rejoin retry loop after a session-invalid close
-- (4006/4009). See the session_invalidated handler below for why a
-- fixed delay isn't reliable. Base/max mirror voice_gateway.lua's own
-- BASE_DELAY_MS/MAX_DELAY_MS reconnect backoff.
local SESSION_INVALID_BASE_DELAY_MS = 500
local SESSION_INVALID_MAX_DELAY_MS = 8000
local MAX_SESSION_INVALID_ATTEMPTS = 8

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
            jitter_buffers = {},
            recording_decoders = {},
            session_invalid_attempts = 0,
        },
        gateway = nil,
        udp = nil,
        _timer = nil,
        _jitter_timer = nil,
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
    self.gateway = VoiceGateway.new(self.client, self.guild.id, self.channel.id)
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
        state.session_invalid_attempts = 0
        self:_on_ready(data)
    end)

    self.gateway:on('client_connect', function(data)
        self:_on_client_connect(data)
    end)

    -- DAVE opcode (11), plural: announces which user IDs are now
    -- expected media session members, with no per-user ssrc (see
    -- clients_connect in voice_gateway.lua's public contract). Only
    -- registers known_users so DAVE add-proposal validation has
    -- something to check against; ssrc mapping still comes from the
    -- legacy client_connect (12) event or from RTP SSRC discovery.
    self.gateway:on('clients_connect', function(data)
        self:_on_clients_connect(data)
    end)

    self.gateway:on('client_disconnect', function(data)
        self:_on_client_disconnect(data)
    end)

    self.gateway:on('speaking', function(data)
        self:_on_speaking(data)
    end)

    -- Session-invalid close code (4006/4009): the gateway already cleared
    -- session_id/token/seq on its side since RESUME would fail against a
    -- dead session. Clear our copy of session_id, token and endpoint too,
    -- so _maybe_connect_gateway won't fire again off stale values.
    --
    -- Re-sending voice_state_update with the same channel_id alone is
    -- not enough to force a fresh VOICE_SERVER_UPDATE: from Discord's
    -- point of view our voice state hasn't changed (still "in" that
    -- channel), so it can reply with only a VOICE_STATE_UPDATE echo
    -- (same session_id, no VOICE_SERVER_UPDATE at all), leaving
    -- token/endpoint nil forever and the reconnect stuck (confirmed
    -- live: session_id was identical across the retry, and no second
    -- voice_server_update ever arrived). Explicitly leaving first
    -- (channel_id=nil) then rejoining forces Discord to treat this as
    -- a real state transition and issue both events again, mirroring
    -- how pycord/discord.py's connect() always restarts the handshake
    -- from a fully torn-down state (prepare_handshake) rather than
    -- assuming the previous channel_id is still "fresh".
    --
    -- A single fixed delay is not reliable: confirmed live that even
    -- with a working leave+rejoin (fresh voice_server_update/token
    -- every retry), Discord's voice session manager can keep handing
    -- back the exact same session_id for several retries in a row
    -- before it actually expires the old one server-side, independent
    -- of anything the client does. Backing off exponentially between
    -- attempts (session_invalid_attempts, reset on ready) gives that
    -- server-side expiry time to happen instead of hammering retries
    -- at a fixed short interval, and MAX_SESSION_INVALID_ATTEMPTS stops
    -- it from retrying forever if the session never clears.
    self.gateway:on('session_invalidated', function(data)
        state.session_id = nil
        state.token = nil
        state.endpoint = nil

        state.session_invalid_attempts = (state.session_invalid_attempts or 0) + 1
        if state.session_invalid_attempts > MAX_SESSION_INVALID_ATTEMPTS then
            state.session_invalid_attempts = 0
            state.connected = false
            self.client:dispatch('VOICE_CLIENT_RECONNECT_FAILED', {
                reason = 'session_invalid_attempts_exceeded',
            })
            return
        end

        self.client:voice_state_update(self.guild.id, nil, false, false)

        local delay = math.min(
            SESSION_INVALID_BASE_DELAY_MS * (2 ^ (state.session_invalid_attempts - 1)),
            SESSION_INVALID_MAX_DELAY_MS
        )
        local rejoin_timer = luv.new_timer()
        rejoin_timer:start(delay, 0, function()
            rejoin_timer:stop()
            self.client:voice_state_update(self.guild.id, self.channel.id, false, false)
        end)

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
    --
    -- VOICE_CLIENT_CONNECTED fires here, not right after select_protocol
    -- in _on_ready: start_recording/audio playback both need
    -- secret_key/mode to actually decrypt or encrypt RTP payloads, and
    -- those only exist once this event arrives (the server's reply to
    -- our select_protocol).
    self.gateway:on('session_description', function(data)
        state.secret_key = data.secret_key
        state.mode = data.mode
        if self.udp then
            self.udp._state.secret_key = data.secret_key
            self.udp._state.mode = data.mode
        end
        local dave_session = self.gateway.state.dave_session
        if dave_session and state.ssrc then
            dave_session:assign_ssrc_to_opus(state.ssrc)
        end
        self.client:dispatch('VOICE_CLIENT_CONNECTED', self)
    end)

    -- Routes decrypted RTP payloads from the UDP client into a per-SSRC
    -- jitter buffer (see opus.PacketDecoder), rather than straight into
    -- the recording sink: UDP can deliver packets out of order, and
    -- feeding them to the sink as they arrive would record them
    -- out of sequence. _flush_jitter_buffers (run on a timer, see
    -- _start_jitter_timer) drains each buffer's packets that have been
    -- held long enough for reordering and hands them to _feed_recording
    -- in ascending RTP sequence order. self.udp._state.on_packet is
    -- udp.lua's real dispatch hook (see UDPClient:_dispatch_packet).
    self.udp._state.on_packet = function(rtp_header, payload)
        local jitter_buffer = state.jitter_buffers[rtp_header.ssrc]
        if not jitter_buffer then
            jitter_buffer = opus.PacketDecoder.new()
            state.jitter_buffers[rtp_header.ssrc] = jitter_buffer
        end
        state.recording_debug = state.recording_debug or { udp = 0, jitter_push = 0, jitter_flush = 0, unknown_ssrc = 0 }
        state.recording_debug.udp = state.recording_debug.udp + 1
        state.recording_debug.jitter_push = state.recording_debug.jitter_push + 1
        jitter_buffer:push_packet(rtp_header, payload)
    end
end

-- Jitter buffer hold window in milliseconds: how long a packet sits
-- buffered before being released, giving a slightly-late or
-- out-of-order packet a chance to arrive and be placed correctly.
-- 60ms is 3 Opus frames at the standard 20ms frame size.
local JITTER_HOLD_MS = 60

-- Drains every active SSRC's jitter buffer of packets that have been
-- held for at least hold_ms (defaults to JITTER_HOLD_MS), delivering
-- them to the matching user's recording sink in ascending RTP sequence
-- order. Called on a timer (see _start_jitter_timer); a no-op if
-- nothing is recording. hold_ms is overridable mainly for tests that
-- need a deterministic flush without waiting on real time.
function VoiceClient:_flush_jitter_buffers(hold_ms)
    local state = self.state

    for ssrc, jitter_buffer in pairs(state.jitter_buffers) do
        local user_id = state.ssrc_map[ssrc]
        local ready = jitter_buffer:pop_ready(hold_ms or JITTER_HOLD_MS)
        state.recording_debug = state.recording_debug or { udp = 0, jitter_push = 0, jitter_flush = 0, unknown_ssrc = 0 }
        state.recording_debug.jitter_flush = state.recording_debug.jitter_flush + #ready

        if user_id then
            for _, entry in ipairs(ready) do
                self:_feed_recording(user_id, entry.payload)
            end
        elseif #ready > 0 then
            state.recording_debug.unknown_ssrc = state.recording_debug.unknown_ssrc + #ready
            print(string.format("RECORD DEBUG unknown_ssrc ssrc=%s ready=%d", tostring(ssrc), #ready))
        end
    end
end

-- Starts the timer that periodically flushes jitter buffers into
-- recording sinks. Safe to call more than once; restarts any existing
-- timer rather than creating a second one.
function VoiceClient:_start_jitter_timer()
    if self._jitter_timer then
        self._jitter_timer:stop()
    end

    self._jitter_timer = luv.new_timer()
    self._jitter_timer:start(JITTER_HOLD_MS, JITTER_HOLD_MS, function()
        self:_flush_jitter_buffers()
    end)
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

        if self._jitter_timer then
            self._jitter_timer:stop()
            self._jitter_timer = nil
        end
        state.jitter_buffers = {}

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
    state.session_invalid_attempts = 0

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

        local success, opus_packet = pcall(function()
            return state.encoder:encode(data)
        end)

        if not success then
            return false, opus_packet
        end

        if not opus_packet then
            return false, "Encoding failed"
        end

        local dave_session = self.gateway and self.gateway.state and self.gateway.state.dave_session
        if dave_session and dave_session:ready() then
            local ciphertext, dave_err = dave_session:encrypt_opus(state.ssrc, opus_packet)
            if not ciphertext then
                return false, dave_err
            end
            opus_packet = ciphertext
        end

        -- Send via UDP
        if not self.udp then
            return false, "UDP not connected"
        end

        local udp_ok, udp_err = self.udp:send(opus_packet)
        if not udp_ok then
            return false, udp_err
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

    self._timer = luv.new_timer()
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
function VoiceClient:_process_source(source, _options)
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
-- header: incoming RTP audio is fed to the sink automatically via the
-- per-SSRC jitter buffer once recording is active.
function VoiceClient:start_recording(sink, finished_callback, ...)
    if not self.state.connected then
        return false, "Not connected"
    end
    if self._recording then
        return false, "Already recording"
    end

    sink.vc = self

    self.state.recording_debug = { udp = 0, jitter_push = 0, jitter_flush = 0, unknown_ssrc = 0 }

    local started_at_ms = luv.now()
    self._recording = {
        sink = sink,
        finished_callback = finished_callback,
        args = { ... },
        timing = {
            started_at_ms = started_at_ms,
            started_wall = os.date("%Y-%m-%d %H:%M:%S"),
        },
        stats = {
            feed = 0,
            dave_enter = 0,
            dave_success = 0,
            dave_failure = 0,
            opus_enter = 0,
            opus_success = 0,
            opus_failure = 0,
            sink_write = 0,
            sink_bytes = 0,
        },
    }

    return true
end

-- Returns a per-user Opus decoder for the recording pipeline, creating
-- one on first use. Each user needs its own decoder instance: libopus
-- decoder state (packet loss concealment, sample history) is per-stream,
-- and mixing SSRCs through one decoder would corrupt the decoded audio.
-- Returns nil if libopus/FFI is not available (e.g. PUC Lua).
function VoiceClient:_get_recording_decoder(user_id)
    local state = self.state
    local decoder = state.recording_decoders[user_id]
    if decoder then
        return decoder
    end

    decoder = opus.Decoder.new()
    if not decoder or not decoder.decoder then
        return nil
    end

    state.recording_decoders[user_id] = decoder
    return decoder
end

-- Feeds one Opus RTP payload for user_id into the active recording sink.
-- Called automatically from _flush_jitter_buffers as reordered packets
-- become ready; can also be called directly for tests or manual feeds.
--
-- If libopus is available and the sink hasn't opted out (see
-- self.wants_raw_opus in lib/voice/sinks/opus_sink.lua), the payload is
-- decoded to PCM before being handed to the sink, since sinks like
-- WaveSink/PCMSink expect decoded PCM (see lib/voice/sinks/sink.lua).
-- If decoding is unavailable, opted out, or fails, the raw Opus payload
-- is passed through unchanged.
function VoiceClient:_feed_recording(user_id, opus_data)
    if not self._recording then
        return false, "Not recording"
    end

    local recording = self._recording
    local stats = recording.stats
    local sink = recording.sink
    local data = opus_data

    stats.feed = stats.feed + 1

    if stats.feed <= 20 then
        local hex = {}
        local n = math.min(#data, 16)
        for i = 1, n do
            hex[i] = string.format("%02x", data:byte(i))
        end
        print(string.format(
            "PIPE DEBUG feed=%d user=%s input_len=%d input_hex=%s",
            stats.feed,
            tostring(user_id),
            #data,
            table.concat(hex, " ")
        ))
    end

    local dave_session = self.gateway and self.gateway.state and self.gateway.state.dave_session
    if dave_session and dave_session:ready() then
        stats.dave_enter = stats.dave_enter + 1
        local plaintext, err = dave_session:decrypt_opus_for_user(user_id, data)
        if plaintext then
            stats.dave_success = stats.dave_success + 1
            data = plaintext

            if stats.feed <= 20 then
                local hex = {}
                local n = math.min(#data, 16)
                for i = 1, n do
                    hex[i] = string.format("%02x", data:byte(i))
                end
                print(string.format(
                    "PIPE DEBUG feed=%d DAVE_OK plaintext_len=%d plaintext_hex=%s",
                    stats.feed,
                    #data,
                    table.concat(hex, " ")
                ))
            end
        else
            stats.dave_failure = stats.dave_failure + 1
            if stats.dave_failure <= 20 or stats.dave_failure % 100 == 0 then
                print(string.format("RECORD DEBUG dave_failure feed=%d err=%s len=%d", stats.feed, tostring(err), #data))
            end
            if err == "dave decrypt failed, result code 2" then
                return false, err
            end
        end
    end

    if not sink.wants_raw_opus then
        stats.opus_enter = stats.opus_enter + 1
        local decoder = self:_get_recording_decoder(user_id)
        if decoder then
            local pcm, err = decoder:decode(data)
            if pcm then
                stats.opus_success = stats.opus_success + 1
                data = pcm

                if stats.feed <= 20 then
                    local sample_count = math.floor(#pcm / 2)
                    local min_sample = 32767
                    local max_sample = -32768
                    local sum_abs = 0
                    local zero_crossings = 0
                    local previous = nil

                    for i = 1, sample_count do
                        local lo, hi = pcm:byte(i * 2 - 1, i * 2)
                        local sample = lo + hi * 256
                        if sample >= 32768 then
                            sample = sample - 65536
                        end

                        if sample < min_sample then
                            min_sample = sample
                        end
                        if sample > max_sample then
                            max_sample = sample
                        end

                        sum_abs = sum_abs + math.abs(sample)

                        if previous ~= nil and (
                            (previous < 0 and sample >= 0) or
                            (previous >= 0 and sample < 0)
                        ) then
                            zero_crossings = zero_crossings + 1
                        end

                        previous = sample
                    end

                    print(string.format(
                        "PIPE DEBUG feed=%d OPUS_OK pcm_bytes=%d samples=%d samples_per_channel=%d min=%d max=%d mean_abs=%.1f zero_crossings=%d",
                        stats.feed,
                        #pcm,
                        sample_count,
                        math.floor(sample_count / 2),
                        min_sample,
                        max_sample,
                        sample_count > 0 and sum_abs / sample_count or 0,
                        zero_crossings
                    ))
                end
            else
                stats.opus_failure = stats.opus_failure + 1
                if stats.opus_failure <= 20 or stats.opus_failure % 100 == 0 then
                    print(string.format("RECORD DEBUG opus_failure feed=%d err=%s len=%d", stats.feed, tostring(err), #data))
                end
                return true
            end
        else
            stats.opus_failure = stats.opus_failure + 1
            if stats.opus_failure == 1 then
                print("RECORD DEBUG opus_decoder_unavailable")
            end
            return true
        end
    end

    sink:write(user_id, data)
    stats.sink_write = stats.sink_write + 1
    stats.sink_bytes = stats.sink_bytes + #data

    if stats.sink_write == 1 or stats.sink_write % 100 == 0 then
        print(string.format("RECORD DEBUG feed=%d dave=%d/%d opus=%d/%d sink=%d bytes=%d", stats.feed, stats.dave_success, stats.dave_enter, stats.opus_success, stats.opus_enter, stats.sink_write, stats.sink_bytes))
    end

    return true
end

-- Stops recording, finalizes the sink, and invokes finished_callback,
-- mirrors pycord's vc.stop_recording().
function VoiceClient:stop_recording()
    if not self._recording then
        return false, "Not recording"
    end

    print("STOP DEBUG entering stop_recording")
    local recording = self._recording
    local stats = recording.stats or {}
    recording.timing.stopped_at_ms = luv.now()
    recording.timing.stopped_wall = os.date("%Y-%m-%d %H:%M:%S")
    recording.timing.wall_duration_ms = recording.timing.stopped_at_ms - recording.timing.started_at_ms
    print("RECORD TIMING started=" .. recording.timing.started_wall)
    print("RECORD TIMING stopped=" .. recording.timing.stopped_wall)
    print(string.format("RECORD TIMING elapsed_ms=%d wall_duration=%.3f sec", recording.timing.wall_duration_ms, recording.timing.wall_duration_ms / 1000))
    print(string.format("RECORD TIMING packets=%d", stats.feed or 0))
    if recording.sink.get_recording_timing then
        recording.sink:get_recording_timing()
    end
    local rdebug = self.state.recording_debug or {}
    print(string.format("RECORD DEBUG final udp=%d jitter_push=%d jitter_flush=%d unknown_ssrc=%d feed=%d dave=%d/%d dave_fail=%d opus=%d/%d opus_fail=%d sink=%d bytes=%d", rdebug.udp or 0, rdebug.jitter_push or 0, rdebug.jitter_flush or 0, rdebug.unknown_ssrc or 0, stats.feed or 0, stats.dave_success or 0, stats.dave_enter or 0, stats.dave_failure or 0, stats.opus_success or 0, stats.opus_enter or 0, stats.opus_failure or 0, stats.sink_write or 0, stats.sink_bytes or 0))
    self._recording = nil

    for user_id, decoder in pairs(self.state.recording_decoders) do
        decoder:destroy()
        self.state.recording_decoders[user_id] = nil
    end
    print("STOP DEBUG decoders destroyed")

    recording.sink:cleanup()
    print("STOP DEBUG sink cleaned up")

    if recording.finished_callback then
        local unpack = table.unpack or unpack -- luacheck: ignore
        recording.finished_callback(recording.sink, unpack(recording.args))
    end
    print("STOP DEBUG finished_callback returned")

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

        -- IP discovery must complete (and yield while it waits, see
        -- udp.lua's discover_ip) before SELECT_PROTOCOL can be sent:
        -- Discord needs our externally-visible address/port, not our
        -- local bind address, and select_protocol is what triggers the
        -- server's SESSION_DESCRIPTION reply carrying secret_key. This
        -- handler already runs inside a coroutine (see ws_adapter.lua's
        -- receive loop), so the yield here is safe.
        local discovered_ip, discovered_port = self.udp:discover_ip()
        if discovered_ip and discovered_port then
            self:_start_jitter_timer()
            if self.gateway then
                self.gateway:select_protocol(discovered_ip, discovered_port)
            end
        else
            self.client:dispatch('VOICE_CLIENT_RECONNECT_FAILED', {
                reason = 'ip_discovery_failed',
            })
            return false
        end
    end

    return true
end

-- Internal: on clients connect (DAVE opcode 11, plural, no ssrc). See
-- the clients_connect listener in setup() for why this is separate from
-- _on_client_connect.
function VoiceClient:_on_clients_connect(data)
    local state = self.state
    local user_ids = data.user_ids or {}
    for _, user_id in ipairs(user_ids) do
        if not state.known_users[user_id] then
            state.known_users[user_id] = { user_id = user_id }
        end
    end
    return true
end

-- Internal: on client connect (legacy singular opcode 12, has ssrc)
function VoiceClient:_on_client_connect(data)
    local state = self.state
    state.known_users[data.user_id] = data
    if data.ssrc then
        state.ssrc_map[data.ssrc] = data.user_id
    end

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
    if data.ssrc then
        state.ssrc_map[data.ssrc] = nil
        state.jitter_buffers[data.ssrc] = nil
    end

    -- Dispatch event
    self.client:dispatch('VOICE_CLIENT_DISCONNECT', {
        user_id = data.user_id,
        ssrc = data.ssrc,
    })

    return true
end

-- Internal: on speaking update. This is the only event that carries
-- both user_id and ssrc together when the peer joined via the plural
-- CLIENTS_CONNECT (DAVE opcode 11, see _on_clients_connect), which has
-- no ssrc at all. Without this, state.ssrc_map never gets populated for
-- DAVE-joined peers and _flush_jitter_buffers silently drops every
-- packet from them (user_id lookup returns nil).
function VoiceClient:_on_speaking(data)
    local state = self.state
    if data.ssrc and data.user_id then
        state.ssrc_map[data.ssrc] = data.user_id
    end

    -- Dispatch event
    self.client:dispatch('VOICE_SPEAKING', {
        user_id = data.user_id,
        ssrc = data.ssrc,
        speaking = data.speaking,
    })

    return true
end

return VoiceClient
