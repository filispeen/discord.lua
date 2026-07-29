-- lib/voice/opus.lua
-- Opus codec wrapper using FFI
--
-- Public Contract:
--   Opus encoder/decoder for voice audio
--     Encoder:new(options) - Create encoder
--     encoder:encode(pcm_data) - Encode PCM to Opus packet
--     encoder:destroy() - Cleanup encoder
--     Decoder:new() - Create decoder
--     decoder:decode(opus_packet) - Decode Opus to PCM
--     decoder:destroy() - Cleanup decoder

local ffi_ok, ffi = pcall(require, "ffi")
if not ffi_ok then
    ffi = nil
end

-- Load libopus
local opus_lib = nil
local function load_opus()
    if not ffi_ok then
        -- Not running under LuaJIT, ffi unavailable
        return
    end

    if opus_lib then return end

    local success = pcall(function()
        opus_lib = ffi.load("opus") or ffi.load("libopus")
    end)

    if not success then
        -- libopus not available, return nil
        return
    end

    ffi.cdef([[
        typedef struct OpusEncoder OpusEncoder;
        typedef struct OpusDecoder OpusDecoder;

        OpusEncoder *opus_encoder_create(int32_t Fs, int channels, int application, int *error);
        void opus_encoder_destroy(OpusEncoder *st);
        int opus_encoder_ctl(OpusEncoder *st, int request, ...);
        int32_t opus_encode(OpusEncoder *st, const int16_t *pcm, int frame_size, unsigned char *data, int32_t max_data_bytes);

        OpusDecoder *opus_decoder_create(int32_t Fs, int channels, int *error);
        void opus_decoder_destroy(OpusDecoder *st);
        int opus_decode(OpusDecoder *st, const unsigned char *data, int32_t len, int16_t *pcm, int frame_size, int decode_fec);

        int32_t opus_packet_get_nb_samples(const unsigned char packet[], int32_t len, int32_t Fs);
        int opus_packet_get_nb_frames(const unsigned char packet[], int32_t len);
    ]])

end

load_opus()

-- Application types (from opus_defines.h)
local APPLICATION_VOIP = 2048
local APPLICATION_AUDIO = 2049
local APPLICATION_LOWDELAY = 2051

-- opus_encoder_ctl request codes (from opus_defines.h)
local OPUS_SET_BITRATE_REQUEST = 4002
local OPUS_SET_BANDWIDTH_REQUEST = 4008
local OPUS_SET_INBAND_FEC_REQUEST = 4012
local OPUS_SET_PACKET_LOSS_PERC_REQUEST = 4014
local OPUS_SET_SIGNAL_REQUEST = 4024

local OPUS_AUTO = -1000
local OPUS_SIGNAL_VOICE = 3001
local OPUS_SIGNAL_MUSIC = 3002

-- Sample rate (Discord voice is always 48kHz stereo)
local SAMPLE_RATE = 48000
local CHANNELS = 2

-- Bandwidth types
local BANDWIDTH_NARROW = 1101
local BANDWIDTH_MEDIUM = 1102
local BANDWIDTH_WIDE = 1103
local BANDWIDTH_SUPERWIDE = 1104
local BANDWIDTH_FULL = 1105

local Opus = {}
Opus.__index = Opus

function Opus.new()
    local self = {
        encoder = nil,
        decoder = nil,
        packet_decoder = nil,
        ssrc = nil,
    }
    setmetatable(self, Opus)
    return self
end

function Opus:load_lib() -- luacheck: ignore
    load_opus()
end

-- Create encoder
function Opus:create_encoder(options)
    if not opus_lib then
        return false, "libopus not available"
    end

    local application = options.application or APPLICATION_AUDIO
    local bitrate = options.bitrate or 64000
    local fec = options.fec
    if fec == nil then
        fec = true
    end
    local expected_packet_loss = options.expected_packet_loss or 15
    local bandwidth = options.bandwidth or BANDWIDTH_FULL
    local signal_type_map = {
        auto = OPUS_AUTO,
        voice = OPUS_SIGNAL_VOICE,
        music = OPUS_SIGNAL_MUSIC,
    }
    local signal_type = signal_type_map[options.signal_type] or OPUS_AUTO

    local err = ffi.new("int[1]")
    local encoder = opus_lib.opus_encoder_create(SAMPLE_RATE, CHANNELS, application, err)

    if err[0] < 0 or encoder == nil then
        return false, "Failed to create opus encoder: " .. tostring(err[0])
    end

    opus_lib.opus_encoder_ctl(encoder, OPUS_SET_BITRATE_REQUEST, ffi.new("int", bitrate))
    opus_lib.opus_encoder_ctl(encoder, OPUS_SET_INBAND_FEC_REQUEST, ffi.new("int", fec and 1 or 0))
    opus_lib.opus_encoder_ctl(encoder, OPUS_SET_PACKET_LOSS_PERC_REQUEST, ffi.new("int", expected_packet_loss))
    opus_lib.opus_encoder_ctl(encoder, OPUS_SET_BANDWIDTH_REQUEST, ffi.new("int", bandwidth))
    opus_lib.opus_encoder_ctl(encoder, OPUS_SET_SIGNAL_REQUEST, ffi.new("int", signal_type))

    self.encoder = encoder
    self.frame_size = math.floor(SAMPLE_RATE * 20 / 1000)  -- 20ms frames

    return true
end

-- Encode PCM to Opus packet. pcm_data must be a raw byte string containing
-- frame_size * CHANNELS 16-bit PCM samples (20ms of 48kHz stereo audio).
-- Returns the encoded packet as a Lua string and its length, or nil on
-- failure.
function Opus:encode(pcm_data)
    if not opus_lib or not self.encoder then
        return nil
    end

    local frame_size = self.frame_size or math.floor(SAMPLE_RATE * 20 / 1000)
    local pcm = ffi.cast("const int16_t*", pcm_data)
    local max_data_bytes = 4000
    local out = ffi.new("unsigned char[?]", max_data_bytes)

    local status = opus_lib.opus_encode(
        self.encoder,
        pcm,
        frame_size,
        out,
        max_data_bytes
    )

    if status < 0 then
        return nil
    end

    return ffi.string(out, status), status
end

-- Create decoder
function Opus:create_decoder()
    if not opus_lib then
        return false, "libopus not available"
    end

    local err = ffi.new("int[1]")
    local decoder = opus_lib.opus_decoder_create(SAMPLE_RATE, CHANNELS, err)

    if err[0] < 0 or decoder == nil then
        return false, "Failed to create opus decoder: " .. tostring(err[0])
    end

    self.decoder = decoder
    return true
end

-- Decode Opus packet to PCM. opus_packet must be a raw byte string.
-- Returns decoded PCM as a Lua string (frame_size * CHANNELS 16-bit
-- samples) and the frame_size (samples per channel), or nil on failure.
function Opus:decode(opus_packet)
    if not opus_lib then
        return nil
    end

    if not self.decoder then
        error("Decoder not initialized")
        return nil
    end

    local max_frame_size = math.floor(SAMPLE_RATE * 120 / 1000)  -- 120ms max
    local pcm = ffi.new("int16_t[?]", max_frame_size * CHANNELS)

    local status = opus_lib.opus_decode(
        self.decoder,
        opus_packet,
        #opus_packet,
        pcm,
        max_frame_size,
        0  -- decode_fec
    )

    if status < 0 then
        return nil
    end

    return ffi.string(pcm, status * CHANNELS * ffi.sizeof("int16_t")), status
end

-- Create packet decoder (jitter buffer)
function Opus:create_packet_decoder(router, ssrc) -- luacheck: ignore
    local decoder = {
        router = router,
        ssrc = ssrc,
        packets = {},
        sequence = 0,
        last_sequence = 0,
    }
    setmetatable(decoder, { __index = decoder })
    return decoder
end

-- TODO: this jitter buffer is not wired into the live RTP receive path
-- (see PROG.md). timestamp/sequence must come from the RTP header, not
-- from libopus (opus_packet_get_timestamp/get_sequence_number/get_size
-- do not exist in the real libopus API and were removed from the FFI
-- bindings above as part of the encoder/decoder fix).
function Opus:packet_decoder_push_packet(packet, rtp_header)
    if not opus_lib then
        return
    end

    if not rtp_header then
        return
    end

    table.insert(self.packets, {
        timestamp = rtp_header.timestamp,
        sequence = rtp_header.sequence,
        packet = packet,
        size = #packet,
    })

    self.sequence = rtp_header.sequence
    self.last_sequence = rtp_header.sequence
end

function Opus:packet_decoder_pop_data(timeout_ms)
    if not opus_lib then
        return nil
    end

    local now = os.time() * 1000
    local current_time = now

    -- Filter packets within timeout
    local valid_packets = {}
    for _, p in ipairs(self.packets) do
        if current_time - p.timestamp <= timeout_ms then
            table.insert(valid_packets, p)
        end
    end

    if #valid_packets == 0 then
        return nil
    end

    -- Sort by sequence and find largest gap
    table.sort(valid_packets, function(a, b)
        return a.sequence < b.sequence
    end)

    local best_packet = valid_packets[1]
    local max_gap = -1

    for i = 2, #valid_packets do
        local gap = valid_packets[i].sequence - valid_packets[i-1].sequence - 1
        if gap > max_gap then
            max_gap = gap
            best_packet = valid_packets[i - 1]
        end
    end

    return best_packet
end

function Opus:packet_decoder_reset()
    self.packets = {}
    self.sequence = 0
    self.last_sequence = 0
end

local Encoder = {
    new = function(options)
        local opus = Opus.new()
        opus:create_encoder(options)
        return opus
    end,
    encode = function(self, pcm_data)
        return self:encode(pcm_data)
    end,
    destroy = function(self)
        if self.encoder then
            if opus_lib then
                opus_lib.opus_encoder_destroy(self.encoder)
            end
            self.encoder = nil
        end
    end,
}

local Decoder = {
    new = function()
        local opus = Opus.new()
        opus:create_decoder()
        return opus
    end,
    decode = function(self, opus_packet)
        return self:decode(opus_packet)
    end,
    destroy = function(self)
        if self.decoder then
            if opus_lib then
                opus_lib.opus_decoder_destroy(self.decoder)
            end
            self.decoder = nil
        end
    end,
}

local PacketDecoder = {
    new = function(router, ssrc)
        return Opus:new():create_packet_decoder(router, ssrc)
    end,
    push_packet = function(self, packet)
        return self:packet_decoder_push_packet(packet)
    end,
    pop_data = function(self, timeout_ms)
        return self:packet_decoder_pop_data(timeout_ms)
    end,
    reset = function(self)
        return self:packet_decoder_reset()
    end,
}

local M = {
    Opus = Opus,
    Encoder = Encoder,
    Decoder = Decoder,
    PacketDecoder = PacketDecoder,
    APPLICATION_AUDIO = APPLICATION_AUDIO,
    APPLICATION_VOIP = APPLICATION_VOIP,
    APPLICATION_LOWDELAY = APPLICATION_LOWDELAY,
    BANDWIDTH_NARROW = BANDWIDTH_NARROW,
    BANDWIDTH_MEDIUM = BANDWIDTH_MEDIUM,
    BANDWIDTH_WIDE = BANDWIDTH_WIDE,
    BANDWIDTH_SUPERWIDE = BANDWIDTH_SUPERWIDE,
    BANDWIDTH_FULL = BANDWIDTH_FULL,
}

return M
