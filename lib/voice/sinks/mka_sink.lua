-- lib/voice/sinks/mka_sink.lua
-- MKASink, contract mirrors pycord's discord.sinks.MKASink. See
-- lib/voice/sinks/opus_sink.lua: this does NOT produce a real Matroska
-- audio container, it stores raw concatenated Opus payloads under the
-- .mka extension. Real Matroska muxing needs a container writer wired
-- into :cleanup().

local class = require("core.class")
local OpusSink = require("voice.sinks.opus_sink")

local MKASink = class("MKASink", OpusSink)

function MKASink.new(opts)
    return setmetatable(OpusSink.new(opts, "mka"), MKASink)
end

return MKASink
