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

local C = ffi_ok and ffi.C or nil

-- Load libopus
local opus_lib = nil
local function load_opus()
    if not ffi_ok then
        -- Not running under LuaJIT, ffi unavailable
        return
    end

    if opus_lib then return end

    local success, err = pcall(function()
        opus_lib = ffi.load("opus") or ffi.load("libopus")
    end)

    if not success then
        -- libopus not available, return nil
        return
    end

    -- Declare opus functions
    C.opus_encoder_create = ffi.cast("int (*)(opus_int32, int, int, opus_int64*)", opus_lib.opus_encoder_create)
    C.opus_encoder_destroy = ffi.cast("void (*)(opus_int32)", opus_lib.opus_encoder_destroy)
    C.opus_encode = ffi.cast("opus_int16 (*)(opus_int32, const opus_int16*, opus_int32, unsigned char*, opus_size_t, int, int)", opus_lib.opus_encode)
    C.opus_encoder_get_frame_size = ffi.cast("opus_int32 (*)(opus_int32, int, int)", opus_lib.opus_encoder_get_frame_size)

    C.opus_decoder_create = ffi.cast("int (*)(opus_int32, int, opus_int64*)", opus_lib.opus_decoder_create)
    C.opus_decoder_destroy = ffi.cast("void (*)(opus_int32)", opus_lib.opus_decoder_destroy)
    C.opus_decode = ffi.cast("opus_int16 (*)(opus_int32, const unsigned char*, int, int, int, int)", opus_lib.opus_decode)

    C.opus_packet_get_size = ffi.cast("size_t (*)(const opus_packet)", opus_lib.opus_packet_get_size)
    C.opus_packet_get_timestamp = ffi.cast("opus_int64 (*)(const opus_packet)", opus_lib.opus_packet_get_timestamp)
    C.opus_packet_get_sequence_number = ffi.cast("opus_uint32 (*)(const opus_packet)", opus_lib.opus_packet_get_sequence_number)

    -- Frame sizes for different application types
    C.opus_encode_get_size = ffi.cast("opus_int32 (*)(opus_int32, int, int)", opus_lib.opus_encode_get_size)
    C.opus_decode_get_size = ffi.cast("opus_int32 (*)(opus_int32, int, int)", opus_lib.opus_decode_get_size)

    -- Packet decoder functions
    C.opus_packet_decode = ffi.cast("int (*)(const opus_packet, const opus_packet*, int, int)", opus_lib.opus_packet_decode)
    C.opus_packet_decode_size = ffi.cast("size_t (*)(const opus_packet*)", opus_lib.opus_packet_decode_size)
end

-- Application types
local APPLICATION_AUDIO = 1
local APPLICATION_VOIP = 2
local APPLICATION_LOWDELAY = 3

-- Bandwidth types
local BANDWIDTH_NARROW = 11025
local BANDWIDTH_MEDIUM = 12000
local BANDWIDTH_WIDE = 16000
local BANDWIDTH_SUPERWIDE = 24000
local BANDWIDTH_FULL = 48000

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

function Opus:load_lib()
    load_opus()
    opus_lib = opus_lib
end

-- Create encoder
function Opus:create_encoder(options)
    if not opus_lib then
        return false, "libopus not available"
    end

    local application = options.application or APPLICATION_AUDIO
    local bitrate = options.bitrate or 128
    local fec = options.fec or true
    local expected_packet_loss = options.expected_packet_loss or 0.15
    local bandwidth = options.bandwidth or BANDWIDTH_FULL
    local signal_type = options.signal_type or "auto"

    local error
    local encoder = ffi.new("opus_int32[1]")
    local status = C.opus_encoder_create(
        APPLICATION_LOWDELAY,  -- Low latency for voice
        bitrate,
        expected_packet_loss,
        encoder[0]
    )

    if status < 0 then
        error = "Failed to create opus encoder: " .. tostring(status)
        return false, error
    end

    self.encoder = encoder[0]
    return true
end

-- Encode PCM to Opus packet
function Opus:encode(pcm_data)
    if not opus_lib then
        return nil
    end

    local frame_size = C.opus_encoder_get_frame_size(self.encoder, APPLICATION_LOWDELAY, 48000)
    local out_size = C.opus_encode_get_size(self.encoder, APPLICATION_LOWDELAY, 48000)

    local pcm = ffi.cast("opus_int16*", pcm_data)
    local out = ffi.new("unsigned char[1275]")  -- Max Opus packet size

    local status = C.opus_encode(
        self.encoder,
        pcm,
        frame_size,
        out,
        out_size,
        0,  -- nb_samples
        0   -- application
    )

    if status < 0 then
        return nil
    end

    return out, out_size
end

-- Create decoder
function Opus:create_decoder()
    if not opus_lib then
        return false, "libopus not available"
    end

    local error
    local decoder = ffi.new("opus_int32[1]")

    local status = C.opus_decoder_create(
        APPLICATION_LOWDELAY,
        48000,
        decoder[0]
    )

    if status < 0 then
        error = "Failed to create opus decoder: " .. tostring(status)
        return false, error
    end

    self.decoder = decoder[0]
    return true
end

-- Decode Opus packet to PCM
function Opus:decode(opus_packet)
    if not opus_lib then
        return nil
    end

    if not self.decoder then
        error("Decoder not initialized")
        return nil
    end

    local frame_size = C.opus_decode_get_size(self.decoder, APPLICATION_LOWDELAY, 48000)
    local pcm = ffi.new("opus_int16[1200]")  -- Max PCM samples

    local status = C.opus_decode(
        self.decoder,
        opus_packet,
        C.opus_packet_get_size(opus_packet),
        pcm,
        frame_size,
        0,  -- nb_samples
        0   -- application
    )

    if status < 0 then
        return nil
    end

    return ffi.cast("opus_int16*", pcm), frame_size
end

-- Create packet decoder (jitter buffer)
function Opus:create_packet_decoder(router, ssrc)
    local self = {
        router = router,
        ssrc = ssrc,
        packets = {},
        sequence = 0,
        last_sequence = 0,
    }
    setmetatable(self, { __index = self })
    return self
end

function Opus:packet_decoder_push_packet(packet)
    if not opus_lib then
        return
    end

    local timestamp = C.opus_packet_get_timestamp(packet)
    local sequence = C.opus_packet_get_sequence_number(packet)
    local packet_size = C.opus_packet_get_size(packet)

    table.insert(self.packets, {
        timestamp = timestamp,
        sequence = sequence,
        packet = packet,
        size = packet_size,
    })

    self.sequence = sequence
    self.last_sequence = sequence
end

function Opus:packet_decoder_pop_data(timeout_ms)
    if not opus_lib then
        return nil
    end

    local now = os.time() * 1000
    local current_time = now

    -- Filter packets within timeout
    local valid_packets = {}
    for i, p in ipairs(self.packets) do
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
                C.opus_encoder_destroy(self.encoder)
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
                C.opus_decoder_destroy(self.decoder)
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
