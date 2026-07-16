-- spec/voice/voice_enums_spec.lua
-- Tests for voice opcodes and enums

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local enums = require("voice.enums")

describe("Voice Enums", function()
    it("should define IDENTIFY opcode", function()
        assert.equals(0, enums.IDENTIFY)
    end)

    it("should define SELECT_PROTOCOL opcode", function()
        assert.equals(1, enums.SELECT_PROTOCOL)
    end)

    it("should define READY opcode", function()
        assert.equals(2, enums.READY)
    end)

    it("should define HEARTBEAT opcode", function()
        assert.equals(3, enums.HEARTBEAT)
    end)

    it("should define SESSION_DESCRIPTION opcode", function()
        assert.equals(4, enums.SESSION_DESCRIPTION)
    end)

    it("should define SPEAKING opcode", function()
        assert.equals(5, enums.SPEAKING)
    end)

    it("should define HEARTBEAT_ACK opcode", function()
        assert.equals(6, enums.HEARTBEAT_ACK)
    end)

    it("should define RESUME opcode", function()
        assert.equals(7, enums.RESUME)
    end)

    it("should define HELLO opcode", function()
        assert.equals(8, enums.HELLO)
    end)

    it("should define RESUMED opcode", function()
        assert.equals(9, enums.RESUMED)
    end)

    it("should define CLIENTS_CONNECT opcode", function()
        assert.equals(11, enums.CLIENTS_CONNECT)
    end)

    it("should define CLIENT_CONNECT opcode", function()
        assert.equals(12, enums.CLIENT_CONNECT)
    end)

    it("should define CLIENT_DISCONNECT opcode", function()
        assert.equals(13, enums.CLIENT_DISCONNECT)
    end)

    it("should define SUPPORTED_MODES table", function()
        assert.is_table(enums.SUPPORTED_MODES)
        assert.equals(2, #enums.SUPPORTED_MODES)
        assert.equals("xsalsa20_poly1305_suffix", enums.SUPPORTED_MODES[1])
        assert.equals("aead_xchacha20_poly1305_rtpsize", enums.SUPPORTED_MODES[2])
    end)

    it("should define DISCONNECTED state", function()
        assert.equals(0, enums.DISCONNECTED)
    end)

    it("should define CONNECTED state", function()
        assert.equals(8, enums.CONNECTED)
    end)
end)
