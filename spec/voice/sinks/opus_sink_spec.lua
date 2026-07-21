-- spec/voice/sinks/opus_sink_spec.lua
-- Tests for the shared OpusSink base (MP3/OGG/MKA/MKV/MP4/M4A sinks)

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local OpusSink = require("voice.sinks.opus_sink")

describe("OpusSink", function()
    it("sets encoding to the value passed at construction", function()
        local sink = OpusSink.new(nil, "mp3")
        assert.equals("mp3", sink.encoding)
    end)

    it("write collects chunks the same way the base Sink does", function()
        local sink = OpusSink.new(nil, "ogg")
        sink:write("user1", "opuschunk1")
        sink:write("user1", "opuschunk2")

        assert.equals(2, sink.audio_data["user1"].packets)
    end)

    it("cleanup concatenates each user's chunks into a single string", function()
        local sink = OpusSink.new(nil, "mkv")
        sink:write("user1", "abc")
        sink:write("user1", "def")
        sink:cleanup()

        assert.equals("string", type(sink.audio_data["user1"].file))
        assert.equals("abcdef", sink.audio_data["user1"].file)
    end)
end)
