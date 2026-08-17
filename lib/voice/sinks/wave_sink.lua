-- lib/voice/sinks/wave_sink.lua
-- WaveSink: wraps recorded PCM per user in a WAV (RIFF) container,
-- contract mirrors pycord's discord.sinks.WaveSink.
--
-- See lib/voice/sinks/sink.lua for how the RTP receive pipeline feeds
-- write(): it decodes incoming Opus payloads to PCM per user before
-- calling write(), when libopus/FFI is available. This sink assumes it
-- is fed already-decoded PCM (16-bit signed, stereo, 48kHz); without
-- libopus/FFI, write() instead receives raw Opus and the resulting
-- WAV file will not be valid audio.
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

local class = require("../../core/class")
local Sink = require("./sink")

local SAMPLE_RATE = 48000
local CHANNELS = 2
local BITS_PER_SAMPLE = 16

local WaveSink = class("WaveSink", Sink)

function WaveSink.new(opts)
    local self = setmetatable(Sink.new(opts), WaveSink)
    self.encoding = "wav"
    self.pcm_bytes = 0
    self.pcm_frames = 0
    return self
end

function WaveSink:write(user_id, pcm_data)
    Sink.write(self, user_id, pcm_data)
    local frames = #pcm_data / (CHANNELS * (BITS_PER_SAMPLE / 8))
    self.pcm_bytes = self.pcm_bytes + #pcm_data
    self.pcm_frames = self.pcm_frames + frames
end

function WaveSink:get_recording_timing()
    print(string.format("RECORD TIMING pcm_samples=%d", self.pcm_frames * CHANNELS))
    print(string.format("RECORD TIMING pcm_frames=%d", self.pcm_frames))
    print(string.format("RECORD TIMING sample_rate=%d channels=%d", SAMPLE_RATE, CHANNELS))
    print(string.format("RECORD TIMING pcm_duration=%.3f sec", self.pcm_frames / SAMPLE_RATE))
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

local function read_le32(s, offset)
    local b1, b2, b3, b4 = string.byte(s, offset, offset + 3)
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
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
    self.wav_bytes = 0
    self.wav_duration = 0
    for user_id, entry in pairs(self.audio_data) do
        local pcm = table.concat(entry.file)
        local data_size = #pcm
        entry.file = build_wav_header(data_size) .. pcm
        entry.pcm_bytes = data_size
        entry.pcm_frames = data_size / (CHANNELS * (BITS_PER_SAMPLE / 8))
        entry.pcm_samples = entry.pcm_frames * CHANNELS
        entry.wav_bytes = #entry.file
        local header_data_size = read_le32(entry.file, 41)
        local header_sample_rate = read_le32(entry.file, 25)
        local header_channels = string.byte(entry.file, 23) + string.byte(entry.file, 24) * 256
        local header_bits = string.byte(entry.file, 35) + string.byte(entry.file, 36) * 256
        local header_block_align = string.byte(entry.file, 33) + string.byte(entry.file, 34) * 256
        entry.wav_duration = header_data_size / (header_sample_rate * header_channels * (header_bits / 8))
        entry.wav_header_data_size = header_data_size
        self.wav_bytes = self.wav_bytes + entry.wav_bytes
        self.wav_duration = math.max(self.wav_duration, entry.wav_duration)
        print(string.format("RECORD TIMING user=%s pcm_samples=%d pcm_frames=%d pcm_duration=%.3f sec wav_duration=%.3f sec wav_bytes=%d wav_header_data=%d sample_rate=%d channels=%d bits=%d block_align=%d", tostring(user_id), entry.pcm_samples, entry.pcm_frames, entry.pcm_frames / SAMPLE_RATE, entry.wav_duration, entry.wav_bytes, header_data_size, header_sample_rate, header_channels, header_bits, header_block_align))
    end
end

function WaveSink:get_recording_timing()
    print(string.format("RECORD TIMING pcm_samples=%d", self.pcm_frames * CHANNELS))
    print(string.format("RECORD TIMING pcm_frames=%d", self.pcm_frames))
    print(string.format("RECORD TIMING sample_rate=%d channels=%d", SAMPLE_RATE, CHANNELS))
    print(string.format("RECORD TIMING pcm_duration=%.3f sec", self.pcm_frames / SAMPLE_RATE))
end

return WaveSink
