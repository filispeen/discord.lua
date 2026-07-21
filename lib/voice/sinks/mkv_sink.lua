-- lib/voice/sinks/mkv_sink.lua
-- MKVSink, contract mirrors pycord's discord.sinks.MKVSink. See
-- lib/voice/sinks/opus_sink.lua: this does NOT produce a real Matroska
-- video container, it stores raw concatenated Opus payloads under the
-- .mkv extension. Real Matroska muxing needs a container writer wired
-- into :cleanup().

local class = require("core.class")
local OpusSink = require("voice.sinks.opus_sink")

local MKVSink = class("MKVSink", OpusSink)

function MKVSink.new(opts)
    return setmetatable(OpusSink.new(opts, "mkv"), MKVSink)
end

return MKVSink
