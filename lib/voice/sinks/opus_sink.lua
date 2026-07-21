-- lib/voice/sinks/opus_sink.lua
-- Shared base for sinks that store raw Opus payloads per user without any
-- real container muxing (MP3Sink, OGGSink, MKASink, MKVSink, MP4Sink,
-- M4ASink). pycord's versions of these actually decode Opus and mux into
-- their named container/codec (via ffmpeg or similar); this codebase has
-- no audio encoding/muxing library available, so these sinks are honestly
-- documented stubs: they collect the raw Opus RTP payloads per user under
-- the right file extension, but do NOT produce a valid mp3/ogg/mka/mkv/
-- mp4/m4a file. Real encoding requires wiring an external tool (ffmpeg
-- subprocess, or a Lua encoding library) into :cleanup().
--
-- See lib/voice/sinks/sink.lua for the RTP-receive-pipeline limitation
-- that also applies here.
--
-- Public Contract:
--   OpusSink.new(opts, encoding) -> sink
--     encoding: string - the file extension this sink claims to produce
--
--   sink:write(user_id, opus_data) -> nil
--     Appends the raw Opus payload to audio_data[user_id].file, same as
--     the base Sink:write.
--
--   sink:cleanup() -> nil
--     Concatenates each user's collected Opus chunks into a single
--     string, same shape as WaveSink's cleanup output, but the bytes are
--     raw concatenated Opus frames, not a valid container file.

local class = require("core.class")
local Sink = require("voice.sinks.sink")

local OpusSink = class("OpusSink", Sink)

function OpusSink.new(opts, encoding)
    local self = setmetatable(Sink.new(opts), OpusSink)
    self.encoding = encoding
    return self
end

function OpusSink:cleanup()
    for _, entry in pairs(self.audio_data) do
        entry.file = table.concat(entry.file)
    end
end

return OpusSink
