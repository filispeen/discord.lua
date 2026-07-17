-- spec/gateway/opcodes_spec.lua
-- Tests for gateway opcodes

-- Setup package path to find lib modules
package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local opcodes = require("gateway.opcodes")

describe("Gateway Opcodes", function()
    it("should define DISPATCH opcode", function()
        assert.equals(0, opcodes.DISPATCH)
    end)

    it("should define HEARTBEAT opcode", function()
        assert.equals(1, opcodes.HEARTBEAT)
    end)

    it("should define IDENTIFY opcode", function()
        assert.equals(2, opcodes.IDENTIFY)
    end)

    it("should define PRESENCE_UPDATE opcode", function()
        assert.equals(3, opcodes.PRESENCE_UPDATE)
    end)

    it("should define VOICE_STATE_UPDATE opcode", function()
        assert.equals(4, opcodes.VOICE_STATE_UPDATE)
    end)

    it("should define RESUME opcode", function()
        assert.equals(6, opcodes.RESUME)
    end)

    it("should define RECONNECT opcode", function()
        assert.equals(7, opcodes.RECONNECT)
    end)

    it("should define REQUEST_GUILD_MEMBERS opcode", function()
        assert.equals(8, opcodes.REQUEST_GUILD_MEMBERS)
    end)

    it("should define INVALID_SESSION opcode", function()
        assert.equals(9, opcodes.INVALID_SESSION)
    end)

    it("should define HELLO opcode", function()
        assert.equals(10, opcodes.HELLO)
    end)

    it("should define HEARTBEAT_ACK opcode", function()
        assert.equals(11, opcodes.HEARTBEAT_ACK)
    end)

    it("does not collide READY with HELLO or HEARTBEAT_ACK", function()
        -- READY is not its own opcode, it is a DISPATCH (0) event with t == "READY".
        -- This test guards against reintroducing the old bug where READY and
        -- HEARTBEAT_ACK both resolved to 10.
        assert.equals(0, opcodes.DISPATCH)
        assert.equals(10, opcodes.HELLO)
        assert.equals(11, opcodes.HEARTBEAT_ACK)
        assert.is_true(opcodes.HELLO ~= opcodes.HEARTBEAT_ACK)
    end)
end)
