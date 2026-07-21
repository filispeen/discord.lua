-- spec/voice/sinks/pcm_sink_spec.lua
-- Tests for PCMSink

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local PCMSink = require("voice.sinks.pcm_sink")

describe("PCMSink", function()
    it("sets encoding to pcm", function()
        local sink = PCMSink.new()
        assert.equals("pcm", sink.encoding)
    end)

    it("writes chunks without any framing", function()
        local sink = PCMSink.new()
        sink:write("user1", "rawpcmdata")

        assert.equals(1, #sink.audio_data["user1"].file)
        assert.equals("rawpcmdata", sink.audio_data["user1"].file[1])
    end)
end)
