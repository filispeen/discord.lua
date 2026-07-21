-- lib/voice/sinks/wave_sink.lua
-- WaveSink: wraps recorded PCM per user in a WAV (RIFF) container,
-- contract mirrors pycord's discord.sinks.WaveSink.
--
-- See lib/voice/sinks/sink.lua for the RTP-receive-pipeline limitation
-- that applies to every sink in this package. This sink assumes it is
-- fed already-decoded PCM (16-bit signed, stereo, 48kHz), not raw Opus;
-- pairing it with real Opus data requires the not-yet-built Opus decode
-- step described there.
--
-- Public Contract:
--   WaveSink.new(opts) -> sink
--
--   sink:write(user_id, pcm_data) -> nil
--     pcm_data: string of raw 16-bit stereo PCM samples at 48kHz.
--     Appended to audio_data[user_id].file (a list of PCM chunks).
--
--   sink:cleanup() -> nil
--     For every user, replaces audio_data[user_id].file (list of PCM
--     chunks) with a single string: a complete WAV file (44 byte RIFF
--     header + the concatenated PCM data), ready to write to disk.

local class = require("core.class")
local Sink = require("voice.sinks.sink")

local SAMPLE_RATE = 48000
local CHANNELS = 2
local BITS_PER_SAMPLE = 16

local WaveSink = class("WaveSink", Sink)

function WaveSink.new(opts)
    local self = setmetatable(Sink.new(opts), WaveSink)
    self.encoding = "wav"
    return self
end

local function le16(n)
    return string.char(n % 256, math.floor(n / 256) % 256)
end

local function le32(n)
    return string.char(
        n % 256,
        math.floor(n / 256) % 256,
        math.floor(n / 65536) % 256,
        math.floor(n / 16777216) % 256
    )
end

-- Builds a standard 44 byte canonical WAV (RIFF/fmt /data) header for
-- data_size bytes of 16-bit stereo 48kHz PCM.
local function build_wav_header(data_size)
    local byte_rate = SAMPLE_RATE * CHANNELS * (BITS_PER_SAMPLE / 8)
    local block_align = CHANNELS * (BITS_PER_SAMPLE / 8)

    local parts = {
        "RIFF",
        le32(36 + data_size),
        "WAVE",
        "fmt ",
        le32(16),        -- fmt chunk size
        le16(1),         -- audio format: 1 = PCM
        le16(CHANNELS),
        le32(SAMPLE_RATE),
        le32(byte_rate),
        le16(block_align),
        le16(BITS_PER_SAMPLE),
        "data",
        le32(data_size),
    }
    return table.concat(parts)
end

function WaveSink:cleanup()
    for _, entry in pairs(self.audio_data) do
        local pcm = table.concat(entry.file)
        entry.file = build_wav_header(#pcm) .. pcm
    end
end

return WaveSink
