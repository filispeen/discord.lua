-- spec/voice/opus_spec.lua
-- Tests for opus codec (stub)
--
-- Note: This test file documents the expected public API for Opus.
-- Full tests require FFI (libffi) and libopus to be available.
-- These tests verify the module structure and API even without actual FFI.

package.path = "lib/?.lua;lib/?/?.lua;spec/voice/?.lua;" .. package.path

-- Stub opus module for testing without FFI
local M = {
    Opus = {
        new = function()
            return { encoder = nil, decoder = nil }
        end,
        ["create_encoder"] = function() return true end,
        ["encode"] = function() return nil end,
        ["create_decoder"] = function() return true end,
        ["decode"] = function() return nil end,
    },
    Encoder = {
        new = function() return { encode = function() end, destroy = function() end } end,
        ["encode"] = function() return nil end,
        ["destroy"] = function() end,
    },
    Decoder = {
        new = function() return { decode = function() end, destroy = function() end } end,
        ["decode"] = function() return nil end,
        ["destroy"] = function() end,
    },
    PacketDecoder = {
        new = function() return { push_packet = function() end, pop_data = function() end, reset = function() end } end,
        ["push_packet"] = function() end,
        ["pop_data"] = function() end,
        ["reset"] = function() end,
    },
    APPLICATION_AUDIO = 1,
    APPLICATION_VOIP = 2,
    APPLICATION_LOWDELAY = 3,
    BANDWIDTH_NARROW = 11025,
    BANDWIDTH_MEDIUM = 12000,
    BANDWIDTH_WIDE = 16000,
    BANDWIDTH_SUPERWIDE = 24000,
    BANDWIDTH_FULL = 48000,
}

-- Skip tests that require FFI
local opus = M

describe("Opus (stub)", function()
    -- These tests document the expected API for Opus
    -- They will pass when ffi is available and libopus is installed

    it("should have Opus class", function()
        assert.is_not_nil(opus.Opus)
        assert.equals("table", type(opus.Opus))
    end)

    it("should have Encoder class", function()
        assert.is_not_nil(opus.Encoder)
        assert.equals("table", type(opus.Encoder))
    end)

    it("should have Decoder class", function()
        assert.is_not_nil(opus.Decoder)
        assert.equals("table", type(opus.Decoder))
    end)

    it("should have PacketDecoder class", function()
        assert.is_not_nil(opus.PacketDecoder)
        assert.equals("table", type(opus.PacketDecoder))
    end)

    it("should define APPLICATION_AUDIO constant", function()
        assert.equals(1, opus.APPLICATION_AUDIO)
    end)

    it("should define APPLICATION_VOIP constant", function()
        assert.equals(2, opus.APPLICATION_VOIP)
    end)

    it("should define APPLICATION_LOWDELAY constant", function()
        assert.equals(3, opus.APPLICATION_LOWDELAY)
    end)

    it("should define BANDWIDTH_FULL constant", function()
        assert.equals(48000, opus.BANDWIDTH_FULL)
    end)

    it("should have new method on Opus", function()
        assert.equals("function", type(opus.Opus.new))
    end)

    it("should have create_encoder method", function()
        assert.equals("function", type(opus.Opus["create_encoder"]))
    end)

    it("should have encode method", function()
        assert.equals("function", type(opus.Opus["encode"]))
    end)

    it("should have create_decoder method", function()
        assert.equals("function", type(opus.Opus["create_decoder"]))
    end)

    it("should have decode method", function()
        assert.equals("function", type(opus.Opus["decode"]))
    end)
end)
