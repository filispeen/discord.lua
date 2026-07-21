-- lib/voice/sinks/ogg_sink.lua
-- OGGSink, contract mirrors pycord's discord.sinks.OGGSink. See
-- lib/voice/sinks/opus_sink.lua: this does NOT produce a real Ogg
-- container, it stores raw concatenated Opus payloads under the .ogg
-- extension. Real Ogg/Opus muxing needs a container writer wired into
-- :cleanup().

local class = require("core.class")
local OpusSink = require("voice.sinks.opus_sink")

local OGGSink = class("OGGSink", OpusSink)

function OGGSink.new(opts)
    return setmetatable(OpusSink.new(opts, "ogg"), OGGSink)
end

return OGGSink
