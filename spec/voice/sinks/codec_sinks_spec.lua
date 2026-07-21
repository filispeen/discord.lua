-- spec/voice/sinks/codec_sinks_spec.lua
-- Tests for the thin OpusSink subclasses: MP3Sink, OGGSink, MKASink,
-- MKVSink, MP4Sink, M4ASink

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local sinks = {
    { name = "MP3Sink", module = "voice.sinks.mp3_sink", encoding = "mp3" },
    { name = "OGGSink", module = "voice.sinks.ogg_sink", encoding = "ogg" },
    { name = "MKASink", module = "voice.sinks.mka_sink", encoding = "mka" },
    { name = "MKVSink", module = "voice.sinks.mkv_sink", encoding = "mkv" },
    { name = "MP4Sink", module = "voice.sinks.mp4_sink", encoding = "mp4" },
    { name = "M4ASink", module = "voice.sinks.m4a_sink", encoding = "m4a" },
}

for _, spec in ipairs(sinks) do
    describe(spec.name, function()
        local SinkClass = require(spec.module)

        it("sets encoding to " .. spec.encoding, function()
            local sink = SinkClass.new()
            assert.equals(spec.encoding, sink.encoding)
        end)

        it("write and cleanup behave the same as OpusSink", function()
            local sink = SinkClass.new()
            sink:write("user1", "chunk-a")
            sink:write("user1", "chunk-b")
            sink:cleanup()

            assert.equals("chunk-achunk-b", sink.audio_data["user1"].file)
        end)
    end)
end
