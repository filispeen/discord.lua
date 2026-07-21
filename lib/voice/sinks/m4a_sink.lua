-- lib/voice/sinks/m4a_sink.lua
-- M4ASink, contract mirrors pycord's discord.sinks.M4ASink. See
-- lib/voice/sinks/opus_sink.lua: this does NOT produce a real M4A
-- container, it stores raw concatenated Opus payloads under the .m4a
-- extension. Real M4A muxing needs a container writer wired into
-- :cleanup().

local class = require("core.class")
local OpusSink = require("voice.sinks.opus_sink")

local M4ASink = class("M4ASink", OpusSink)

function M4ASink.new(opts)
    return setmetatable(OpusSink.new(opts, "m4a"), M4ASink)
end

return M4ASink
