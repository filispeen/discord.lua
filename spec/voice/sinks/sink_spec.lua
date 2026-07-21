-- spec/voice/sinks/sink_spec.lua
-- Tests for the base Sink class

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local Sink = require("voice.sinks.sink")

describe("Sink", function()
    it("defaults encoding to raw", function()
        local sink = Sink.new()
        assert.equals("raw", sink.encoding)
    end)

    it("starts with empty audio_data", function()
        local sink = Sink.new()
        assert.same({}, sink.audio_data)
    end)

    it("write creates a user entry on first call", function()
        local sink = Sink.new()
        sink:write("user1", "chunk1")

        assert.is_not_nil(sink.audio_data["user1"])
        assert.equals(1, sink.audio_data["user1"].packets)
    end)

    it("write appends multiple chunks for the same user", function()
        local sink = Sink.new()
        sink:write("user1", "chunk1")
        sink:write("user1", "chunk2")

        assert.equals(2, sink.audio_data["user1"].packets)
        assert.equals(2, #sink.audio_data["user1"].file)
    end)

    it("write tracks separate users independently", function()
        local sink = Sink.new()
        sink:write("user1", "a")
        sink:write("user2", "b")

        assert.equals(1, sink.audio_data["user1"].packets)
        assert.equals(1, sink.audio_data["user2"].packets)
    end)

    it("get_all_audio returns audio_data", function()
        local sink = Sink.new()
        sink:write("user1", "a")
        assert.equals(sink.audio_data, sink:get_all_audio())
    end)

    it("get_user_audio returns a single user's entry", function()
        local sink = Sink.new()
        sink:write("user1", "a")
        assert.equals(sink.audio_data["user1"], sink:get_user_audio("user1"))
    end)

    it("get_user_audio returns nil for an unknown user", function()
        local sink = Sink.new()
        assert.is_nil(sink:get_user_audio("unknown"))
    end)

    it("cleanup is a no-op on the base Sink", function()
        local sink = Sink.new()
        sink:write("user1", "a")
        assert.has_no.errors(function()
            sink:cleanup()
        end)
    end)
end)
