-- spec/voice/packet_decoder_spec.lua
-- Tests for opus.lua's PacketDecoder (RTP sequence jitter buffer).
-- Unlike opus_spec.lua, this requires the real module: PacketDecoder is
-- pure Lua with no FFI/libopus dependency, so it runs identically under
-- PUC Lua 5.1 and LuaJIT without needing a real Opus codec.

require("spec_helper")
package.path = "spec/voice/?.lua;" .. package.path

local opus = require("./voice/opus")

local function header(sequence, timestamp)
    return { sequence = sequence, timestamp = timestamp or sequence * 960 }
end

describe("PacketDecoder", function()
    it("is exported from the opus module", function()
        assert.is_not_nil(opus.PacketDecoder)
        assert.equals("table", type(opus.PacketDecoder))
    end)

    it("creates an independent instance per call", function()
        local a = opus.PacketDecoder.new()
        local b = opus.PacketDecoder.new()
        a:push_packet(header(1), "a")
        assert.equals(0, #b:pop_ready(0))
    end)

    it("buffers a pushed packet until pop_ready", function()
        local jb = opus.PacketDecoder.new()
        assert.is_true(jb:push_packet(header(1), "payload-1"))
    end)

    it("rejects a packet with no rtp_header", function()
        local jb = opus.PacketDecoder.new()
        assert.is_false(jb:push_packet(nil, "payload"))
    end)

    it("ignores a duplicate sequence number", function()
        local jb = opus.PacketDecoder.new()
        assert.is_true(jb:push_packet(header(5), "first"))
        assert.is_false(jb:push_packet(header(5), "retransmit"))

        local ready = jb:pop_ready(0)
        assert.equals(1, #ready)
        assert.equals("first", ready[1].payload)
    end)

    it("pop_ready returns nothing before hold_ms has elapsed", function()
        local jb = opus.PacketDecoder.new()
        jb:push_packet(header(1), "payload-1")

        local ready = jb:pop_ready(60000)
        assert.equals(0, #ready)
    end)

    it("pop_ready returns buffered packets once hold_ms has elapsed", function()
        local jb = opus.PacketDecoder.new()
        jb:push_packet(header(1), "payload-1")

        local ready = jb:pop_ready(0)
        assert.equals(1, #ready)
        assert.equals(1, ready[1].sequence)
        assert.equals("payload-1", ready[1].payload)
    end)

    it("reorders out-of-order packets by sequence number", function()
        local jb = opus.PacketDecoder.new()
        jb:push_packet(header(3), "third")
        jb:push_packet(header(1), "first")
        jb:push_packet(header(2), "second")

        local ready = jb:pop_ready(0)
        assert.equals(3, #ready)
        assert.equals("first", ready[1].payload)
        assert.equals("second", ready[2].payload)
        assert.equals("third", ready[3].payload)
    end)

    it("leaves not-yet-ready packets buffered for a later pop_ready call", function()
        local jb = opus.PacketDecoder.new()
        jb:push_packet(header(1), "first")

        local ready = jb:pop_ready(60000)
        assert.equals(0, #ready)

        local ready_again = jb:pop_ready(0)
        assert.equals(1, #ready_again)
        assert.equals("first", ready_again[1].payload)
    end)

    it("handles sequence number wraparound past 65535", function()
        local jb = opus.PacketDecoder.new()
        jb:push_packet(header(65535), "before-wrap")
        jb:push_packet(header(1), "after-wrap")
        jb:push_packet(header(0), "at-wrap")

        local ready = jb:pop_ready(0)
        assert.equals(3, #ready)
        assert.equals("before-wrap", ready[1].payload)
        assert.equals("at-wrap", ready[2].payload)
        assert.equals("after-wrap", ready[3].payload)
    end)

    it("reset drops all buffered packets", function()
        local jb = opus.PacketDecoder.new()
        jb:push_packet(header(1), "payload-1")
        jb:push_packet(header(2), "payload-2")

        jb:reset()

        local ready = jb:pop_ready(0)
        assert.equals(0, #ready)
    end)

    it("allows re-pushing a sequence number after reset", function()
        local jb = opus.PacketDecoder.new()
        jb:push_packet(header(1), "payload-1")
        jb:reset()

        assert.is_true(jb:push_packet(header(1), "payload-1-again"))
    end)
end)
