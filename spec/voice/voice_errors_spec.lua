-- spec/voice/voice_errors_spec.lua
-- Tests for voice errors

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local errors = require("voice.errors")

describe("Voice Errors", function()
    it("should export VoiceClientError", function()
        assert.is_table(errors.VoiceClientError)
    end)

    it("should export VoiceConnectError", function()
        assert.is_table(errors.VoiceConnectError)
    end)

    it("should export VoiceDisconnectError", function()
        assert.is_table(errors.VoiceDisconnectError)
    end)

    it("should export VoiceAudioError", function()
        assert.is_table(errors.VoiceAudioError)
    end)

    it("should create VoiceClientError", function()
        local err = errors.VoiceClientError.new("test error")
        assert.equals("test error", err.message)
    end)

    it("should create VoiceConnectError", function()
        local err = errors.VoiceConnectError.new("connection failed")
        assert.equals("connection failed", err.message)
    end)

    it("should create VoiceDisconnectError", function()
        local err = errors.VoiceDisconnectError.new("disconnected", 1000, "normal close")
        assert.equals("disconnected", err.message)
        assert.equals(1000, err.code)
        assert.equals("normal close", err.reason)
    end)

    it("should create VoiceAudioError", function()
        local err = errors.VoiceAudioError.new("audio processing failed")
        assert.equals("audio processing failed", err.message)
    end)
end)
