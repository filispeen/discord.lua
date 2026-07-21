-- spec/voice/sinks/wave_sink_spec.lua
-- Tests for WaveSink

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local WaveSink = require("voice.sinks.wave_sink")

describe("WaveSink", function()
    it("sets encoding to wav", function()
        local sink = WaveSink.new()
        assert.equals("wav", sink.encoding)
    end)

    it("cleanup produces a string starting with a RIFF/WAVE header", function()
        local sink = WaveSink.new()
        sink:write("user1", "somepcmdata")
        sink:cleanup()

        local file = sink.audio_data["user1"].file
        assert.equals("string", type(file))
        assert.equals("RIFF", file:sub(1, 4))
        assert.equals("WAVE", file:sub(9, 12))
        assert.equals("fmt ", file:sub(13, 16))
        assert.equals("data", file:sub(37, 40))
    end)

    it("cleanup's header declares the correct data size", function()
        local sink = WaveSink.new()
        local pcm = "0123456789"
        sink:write("user1", pcm)
        sink:cleanup()

        local file = sink.audio_data["user1"].file
        assert.equals(44 + #pcm, #file)
    end)

    it("cleanup preserves the original PCM bytes after the 44 byte header", function()
        local sink = WaveSink.new()
        local pcm = "hello-pcm-data"
        sink:write("user1", pcm)
        sink:cleanup()

        local file = sink.audio_data["user1"].file
        assert.equals(pcm, file:sub(45))
    end)

    it("cleanup concatenates multiple written chunks before framing", function()
        local sink = WaveSink.new()
        sink:write("user1", "abc")
        sink:write("user1", "def")
        sink:cleanup()

        local file = sink.audio_data["user1"].file
        assert.equals("abcdef", file:sub(45))
    end)

    it("cleanup processes every user independently", function()
        local sink = WaveSink.new()
        sink:write("user1", "aaa")
        sink:write("user2", "bbbbb")
        sink:cleanup()

        assert.equals(44 + 3, #sink.audio_data["user1"].file)
        assert.equals(44 + 5, #sink.audio_data["user2"].file)
    end)
end)
