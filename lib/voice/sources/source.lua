-- lib/voice/sources/source.lua
-- Base AudioSource class for voice playback, contract mirrors pycord's
-- discord.player.AudioSource.
--
-- See lib/voice/voice_client.lua VoiceClient:_start_playback: a 20ms
-- luv timer calls source:is_playing() then source:read() on each tick,
-- encodes the returned chunk to Opus (state.encoder, fixed 960 samples
-- per frame at 48kHz stereo, see opus.lua) and sends it. A source must
-- therefore return exactly 3840 bytes (960 samples * 2 channels * 2
-- bytes/sample) of raw 16-bit little-endian PCM per read() call, except
-- for the final call which may return a shorter final chunk or nil to
-- signal end of stream.
--
-- Public Contract:
--   AudioSource.new(opts) -> source
--
--   source:read() -> pcm_chunk (string) or nil
--     Returns the next 20ms chunk of raw 16-bit stereo 48kHz PCM, or
--     nil when the source is exhausted (stops playback, see
--     VoiceClient:_start_playback). Subclasses must override this.
--
--   source:is_playing() -> boolean
--     Whether the source still has data to read. Base implementation
--     always returns true; subclasses that track exhaustion (e.g.
--     FileSource at EOF) should override this to return false once
--     read() would return nil, so the playback timer can stop cleanly
--     without waiting on one more read() call.
--
--   source:cleanup() -> nil
--     Called by subclasses' own stop/close paths (not automatically by
--     VoiceClient) to release any held resources (file handles,
--     subprocess pipes). Base implementation is a no-op.

local class = require("../../core/class")

local AudioSource = class("AudioSource")

function AudioSource.new(_opts)
    local self = setmetatable({}, AudioSource)
    return self
end

function AudioSource:read()
    error("AudioSource:read must be implemented by a subclass")
end

function AudioSource:is_playing()
    return true
end

function AudioSource:cleanup()
end

return AudioSource
