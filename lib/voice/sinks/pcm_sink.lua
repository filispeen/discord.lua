-- lib/voice/sinks/pcm_sink.lua
-- PCMSink: writes raw decoded PCM samples per user, contract mirrors
-- pycord's discord.sinks.PCMSink.
--
-- See lib/voice/sinks/sink.lua for the RTP-receive-pipeline limitation
-- that applies to every sink in this package.
--
-- Public Contract:
--   PCMSink.new(opts) -> sink
--   sink:write(user_id, pcm_data) -> nil
--     pcm_data is expected to already be decoded PCM (16-bit stereo,
--     48kHz), not Opus. Appended to audio_data[user_id].file as-is with
--     no framing, matching PCMSink's lack of a container format.

local class = require("core.class")
local Sink = require("voice.sinks.sink")

local PCMSink = class("PCMSink", Sink)

function PCMSink.new(opts)
    local self = setmetatable(Sink.new(opts), PCMSink)
    self.encoding = "pcm"
    return self
end

return PCMSink
