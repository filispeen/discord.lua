-- spec/gateway/opcodes_spec.lua
-- Tests for gateway opcodes

-- Setup package path to find lib modules
package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local opcodes = require("gateway.opcodes")

describe("Gateway Opcodes", function()
    it("should define CONNECT opcode", function()
        assert.equals(0, opcodes.CONNECT)
    end)

    it("should define IDENTIFY opcode", function()
        assert.equals(2, opcodes.IDENTIFY)
    end)

    it("should define READY opcode", function()
        assert.equals(10, opcodes.READY)
    end)

    it("should define HEARTBEAT opcode", function()
        assert.equals(1, opcodes.HEARTBEAT)
    end)

    it("should define HEARTBEAT_ACK opcode", function()
        assert.equals(10, opcodes.HEARTBEAT_ACK)
    end)

    it("should define RESUME opcode", function()
        assert.equals(12, opcodes.RESUME)
    end)

    it("should define DISCONNECTED opcode", function()
        assert.equals(11, opcodes.DISCONNECTED)
    end)

    it("should define RECONNECT opcode", function()
        assert.equals(7, opcodes.RECONNECT)
    end)
end)
