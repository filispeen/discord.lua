-- lib/voice/sinks/mp4_sink.lua
-- MP4Sink, contract mirrors pycord's discord.sinks.MP4Sink. See
-- lib/voice/sinks/opus_sink.lua: this does NOT produce a real MP4
-- container, it stores raw concatenated Opus payloads under the .mp4
-- extension. Real MP4 muxing needs a container writer wired into
-- :cleanup().

local class = require("core.class")
local OpusSink = require("voice.sinks.opus_sink")

local MP4Sink = class("MP4Sink", OpusSink)

function MP4Sink.new(opts)
    return setmetatable(OpusSink.new(opts, "mp4"), MP4Sink)
end

return MP4Sink
