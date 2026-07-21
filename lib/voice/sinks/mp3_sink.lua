-- lib/voice/sinks/mp3_sink.lua
-- MP3Sink, contract mirrors pycord's discord.sinks.MP3Sink. See
-- lib/voice/sinks/opus_sink.lua: this does NOT produce a real MP3 file,
-- it stores raw concatenated Opus payloads under the .mp3 extension.
-- Real MP3 encoding needs an external encoder wired into :cleanup().

local class = require("core.class")
local OpusSink = require("voice.sinks.opus_sink")

local MP3Sink = class("MP3Sink", OpusSink)

function MP3Sink.new(opts)
    return setmetatable(OpusSink.new(opts, "mp3"), MP3Sink)
end

return MP3Sink
