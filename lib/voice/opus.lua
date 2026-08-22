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
--
--   PacketDecoder: pure Lua RTP sequence jitter buffer, no FFI/libopus
--   dependency (see the PacketDecoder class below for the full contract).
--   Uses luv.now() (wall-clock) for hold-time bookkeeping, not
--   os.clock() (CPU time) -- see push_packet's received_at comment.
--     PacketDecoder.new() - Create a jitter buffer
--     jb:push_packet(rtp_header, payload) - Buffer one packet
--     jb:pop_ready(hold_ms?) - Pop packets held >= hold_ms, in sequence order
--     jb:reset() - Drop all buffered packets

local ffi_ok, ffi = pcall(require, "ffi")
if not ffi_ok then
    ffi = nil
end

local native_lib = require("./native_lib")
local luv = require("../core/luv_compat")

-- Load libopus
local opus_lib = nil
local function load_opus()
    if not ffi_ok then
        -- Not running under LuaJIT, ffi unavailable
        return
    end

    if opus_lib then return end

    -- Prefer the dll bundled in lib/dlls/ (see native_lib.lua) on
    -- Windows, since a bare ffi.load("opus") only checks the OS's
    -- normal library search path and won't find it there on its own.
    -- Falls back to the bare name so a system-installed libopus (the
    -- expected setup on Linux/macOS) still works.
    local bundled_path = native_lib.resolve("opus")

    local success = pcall(function()
        if bundled_path then
            opus_lib = ffi.load(bundled_path)
        else
            opus_lib = ffi.load("opus") or ffi.load("libopus")
        end
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

    local application_map = {
        voip = APPLICATION_VOIP,
        audio = APPLICATION_AUDIO,
        lowdelay = APPLICATION_LOWDELAY,
    }
    local application = application_map[options.application] or APPLICATION_AUDIO
    local bitrate = options.bitrate or 64000
    local fec = options.fec
    if fec == nil then
        fec = true
    end
    local expected_packet_loss = options.expected_packet_loss or 15
    local bandwidth_map = {
        narrow = BANDWIDTH_NARROW,
        medium = BANDWIDTH_MEDIUM,
        wide = BANDWIDTH_WIDE,
        superwide = BANDWIDTH_SUPERWIDE,
        full = BANDWIDTH_FULL,
    }
    local bandwidth = bandwidth_map[options.bandwidth] or BANDWIDTH_FULL
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

-- Cleanup encoder and/or decoder held by this instance. Both
-- opus.Encoder.new()/opus.Decoder.new() return an Opus instance (see
-- Opus.new()), so destroy lives here, not on the unused Encoder/Decoder
-- wrapper tables below (their metatable is never actually assigned).
function Opus:destroy()
    if self.encoder then
        if opus_lib then
            opus_lib.opus_encoder_destroy(self.encoder)
        end
        self.encoder = nil
    end

    if self.decoder then
        if opus_lib then
            opus_lib.opus_decoder_destroy(self.decoder)
        end
        self.decoder = nil
    end
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



local Encoder = {
    -- Takes an explicit (ignored) self so opus.Encoder:new(options)
    -- colon-call syntax (the only call site, voice_client.lua) works
    -- correctly: colon-call auto-passes Encoder itself as the first
    -- argument, so without this explicit self param, that first slot
    -- silently ate the Encoder table and the real options table -- the
    -- second argument -- was dropped entirely. create_encoder then saw
    -- options=nil for every field, so bitrate/fec/expected_packet_loss/
    -- bandwidth/application/signal_type all silently fell back to
    -- create_encoder's own hardcoded defaults regardless of what was
    -- actually passed in, for as long as this file has existed. This
    -- masked all three settings fixed earlier this session (bitrate,
    -- expected_packet_loss units, application mode): the corrected
    -- values were being written into a table that never reached
    -- create_encoder at all.
    new = function(_, options)
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
    -- Explicit (ignored) self for the same colon-call reason as
    -- Encoder.new above; harmless today since create_decoder takes no
    -- options, but kept consistent so a future option added here does
    -- not silently repeat the exact same bug.
    new = function(_)
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

-- Jitter buffer: reorders incoming RTP-decoded Opus payloads by RTP
-- sequence number before handing them to the caller, so a packet that
-- arrives out of order (common over UDP) isn't delivered before an
-- earlier one that is still in flight. Pure Lua, no FFI/libopus
-- dependency, so it works identically under PUC Lua and LuaJIT.
--
-- Usage:
--   local jb = PacketDecoder.new()
--   jb:push_packet(rtp_header, payload)   -- call per received packet
--   local ready = jb:pop_ready(hold_ms)   -- call periodically (e.g. from
--                                          -- a timer); returns a list of
--                                          -- { sequence, timestamp, payload }
--                                          -- in ascending sequence order
--                                          -- for packets that have sat in
--                                          -- the buffer at least hold_ms
--   jb:reset()                            -- drop all buffered packets
--
-- Sequence numbers are 16 bit (0-65535) and wrap around; comparisons use
-- signed 16 bit difference arithmetic so a wrapped sequence still sorts
-- correctly relative to recent ones.
local PacketDecoder = {}
PacketDecoder.__index = PacketDecoder

local SEQ_MOD = 65536
local SEQ_HALF = 32768

-- Signed difference a - b for 16 bit RTP sequence numbers, wrapping the
-- result into (-32768, 32768] so it reflects "how many packets after b
-- is a", even across a 65535 -> 0 wraparound.
local function seq_diff(a, b)
    local diff = (a - b) % SEQ_MOD
    if diff > SEQ_HALF then
        diff = diff - SEQ_MOD
    end
    return diff
end

function PacketDecoder.new()
    local self = setmetatable({}, PacketDecoder)
    self.packets = {}
    self.by_sequence = {}
    self.highest_sequence = nil
    return self
end

-- Buffer one packet. rtp_header must have .sequence and .timestamp
-- (as produced by udp.lua's parse_rtp_header). Duplicate sequence
-- numbers (retransmits or replays) are ignored after the first.
function PacketDecoder:push_packet(rtp_header, payload)
    if not rtp_header or not rtp_header.sequence then
        return false
    end

    local sequence = rtp_header.sequence
    if self.by_sequence[sequence] then
        return false
    end

    local entry = {
        sequence = sequence,
        timestamp = rtp_header.timestamp,
        payload = payload,
        -- luv.now() (libuv's monotonic clock, milliseconds) not
        -- os.clock(): os.clock() measures CPU time consumed by this
        -- process, not wall-clock time. In an event-driven Luvit
        -- process that spends nearly all of its time asleep waiting on
        -- I/O between packets, CPU time barely advances between two
        -- packets received 20ms apart in the real world -- so
        -- `now - entry.received_at >= hold_ms` in pop_ready almost
        -- never became true on schedule. Packets piled up in the
        -- buffer far longer than the intended 60ms reorder window,
        -- and were eventually flushed in one large, badly-stale batch
        -- once accumulated CPU time happened to cross the threshold
        -- (which could correspond to seconds or minutes of real time
        -- under light load). Each payload string itself was still
        -- byte-correct, but by the time it reached decrypt_opus_for_user
        -- the MLS epoch/key ratchet for that sender had typically moved
        -- on, since real wall-clock time -- during which WELCOME/COMMIT/
        -- EXECUTE_TRANSITION could easily have rotated keys -- had
        -- elapsed far beyond what the stale received_at implied. This
        -- surfaced downstream as garbled-looking ciphertext being fed
        -- to a decryptor keyed for a different epoch than what
        -- encrypted it.
        received_at = luv.now(),
    }

    self.by_sequence[sequence] = entry
    table.insert(self.packets, entry)

    if not self.highest_sequence or seq_diff(sequence, self.highest_sequence) > 0 then
        self.highest_sequence = sequence
    end

    return true
end

-- Returns the buffered packets that have waited at least hold_ms,
-- oldest sequence first, and removes them from the buffer. Packets
-- still younger than hold_ms are left buffered for a future call, so
-- a packet that arrives slightly out of order still has a chance to be
-- delivered in the right place. hold_ms defaults to 60ms (3 frames at
-- 20ms/frame), a reasonable reorder window for typical jitter.
function PacketDecoder:pop_ready(hold_ms)
    hold_ms = hold_ms or 60

    if #self.packets == 0 then
        return {}
    end

    table.sort(self.packets, function(a, b)
        return seq_diff(a.sequence, b.sequence) < 0
    end)

    -- luv.now(), matching push_packet's received_at (see comment
    -- there for why os.clock() -- CPU time, not wall-clock -- was
    -- wrong here).
    local now = luv.now()
    local ready = {}
    local remaining = {}

    for _, entry in ipairs(self.packets) do
        if now - entry.received_at >= hold_ms then
            table.insert(ready, entry)
            self.by_sequence[entry.sequence] = nil
        else
            table.insert(remaining, entry)
        end
    end

    self.packets = remaining
    return ready
end

function PacketDecoder:reset()
    self.packets = {}
    self.by_sequence = {}
    self.highest_sequence = nil
end

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
