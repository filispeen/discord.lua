-- lib/voice/sources/pcm_source.lua
-- PCMSource: reads raw 16-bit 48kHz stereo PCM from a file, contract
-- mirrors pycord's discord.player.PCMAudio.
--
-- See lib/voice/sources/source.lua for the AudioSource read()/
-- is_playing() contract this fulfills.
--
-- Public Contract:
--   PCMSource.new(path) -> source
--     path: string - filesystem path to a raw PCM file (no container/
--     header, just interleaved 16-bit little-endian stereo samples at
--     48kHz, e.g. produced by `ffmpeg -f s16le -ar 48000 -ac 2`).
--     Errors if the file cannot be opened.
--
--   source:read() -> pcm_chunk (string) or nil
--     Returns exactly 3840 bytes (960 samples * 2 channels * 2 bytes)
--     per call. Once fewer than 3840 bytes remain, those trailing bytes
--     are discarded (not padded or sent as a short frame, matching
--     pycord's PCMAudio) and read() returns nil, matching pycord's
--     stream returning less than FRAME_SIZE bytes at EOF.
--
--   The entire file is read into memory once, in the constructor, and
--   read() slices from that in-memory buffer. This is not just a small
--   optimization: source:read() runs synchronously on every 20ms tick
--   of VoiceClient's playback luv timer (see voice_client.lua
--   _start_playback), and any per-tick disk I/O blocks that timer's
--   entire event loop turn. On a WSL-mounted Windows drive (9p
--   protocol, e.g. this project's /mnt/f path) individual file reads
--   can occasionally stall for tens to hundreds of milliseconds with no
--   warning, which previously surfaced as intermittent audio dropouts
--   even after RTP/DAVE delivery was otherwise correct. Reading once
--   upfront removes disk I/O from the hot path entirely.
--
--   source:is_playing() -> boolean
--     False once EOF has been reached (a read() call returned nil or
--     the file ran out), true otherwise.
--
--   source:cleanup() -> nil
--     Releases the in-memory buffer. Safe to call more than once.

local class = require("../../core/class")
local AudioSource = require("./source")

local PCMSource = class("PCMSource", AudioSource)

-- 960 samples/frame * 2 channels * 2 bytes/sample = 3840 bytes per
-- 20ms frame at 48kHz stereo 16-bit PCM.
local FRAME_BYTES = 960 * 2 * 2

function PCMSource.new(path)
    local file, err = io.open(path, "rb")
    if not file then
        error("PCMSource: failed to open " .. tostring(path) .. ": " .. tostring(err))
    end

    local data = file:read("*a")
    file:close()

    local self = setmetatable(AudioSource.new(), PCMSource)
    self._data = data or ""
    self._pos = 1
    self._eof = false
    return self
end

function PCMSource:read()
    if self._eof then
        return nil
    end

    local chunk = self._data:sub(self._pos, self._pos + FRAME_BYTES - 1)
    if #chunk < FRAME_BYTES then
        self._eof = true
        self:cleanup()
        return nil
    end

    self._pos = self._pos + FRAME_BYTES
    return chunk
end

function PCMSource:is_playing()
    return not self._eof
end

function PCMSource:cleanup()
    self._data = nil
end

return PCMSource
