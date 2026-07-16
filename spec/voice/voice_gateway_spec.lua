-- spec/voice/voice_gateway_spec.lua
-- Tests for voice gateway

package.path = "lib/?.lua;lib/?/?.lua;spec/voice/?.lua;" .. package.path

-- Mock luv for testing
local mock_luv = {
    timer = {
        new = function()
            local timer = {
                start = function() end,
                stop = function() end,
            }
            return timer
        end
    },
    socket = function()
        return 1
    end,
    bind = function() end,
    getsockname = function() end,
    onread = function() end,
    sendto = function()
        return true, nil
    end,
    recvfrom = function()
        return nil
    end,
    close = function() end,
}

package.loaded["luv"] = mock_luv

local class = require("core.class")
local enums = require("voice.enums")
local errors = require("voice.errors")

-- Mock WebSocket
local MockWebSocket = class("MockWebSocket")
function MockWebSocket.new()
    local self = {
        messages = {},
    }
    setmetatable(self, MockWebSocket)
    return self
end

function MockWebSocket:send(data)
    table.insert(self.messages, data)
    return true
end

function MockWebSocket:close()
    return true
end

local VoiceGateway = require("voice.voice_gateway")

describe("VoiceGateway", function()
    local mock_client

    before_each(function()
        mock_client = {
            user = { id = "123456789" },
            dispatch = function() end,
        }
    end)

    describe("VoiceGateway creation", function()
        it("should create a new gateway", function()
            local gateway = VoiceGateway.new(mock_client, "guild123")
            assert.is_not_nil(gateway)
            assert.equals("guild123", gateway.guild_id)
            assert.equals(mock_client, gateway.client)
        end)

        it("should have state table", function()
            local gateway = VoiceGateway.new(mock_client, "guild123")
            assert.is_true(type(gateway.state) == "table")
        end)

        it("should have gateway state set to DISCONNECTED", function()
            local gateway = VoiceGateway.new(mock_client, "guild123")
            assert.equals(enums.DISCONNECTED, gateway.state.state)
        end)
    end)

    describe("Identify", function()
        local gateway

        before_each(function()
            gateway = VoiceGateway.new(mock_client, "guild123")
            gateway.ws = MockWebSocket.new()
        end)

        it("should send identify payload", function()
            local success, err = pcall(function()
                gateway:identify()
            end)

            assert.is_true(success)
            assert.equals(1, #gateway.ws.messages)
            assert.equals(enums.IDENTIFY, gateway.ws.messages[1].op)
        end)
    end)

    describe("Send heartbeat", function()
        local gateway

        before_each(function()
            gateway = VoiceGateway.new(mock_client, "guild123")
            gateway.ws = MockWebSocket.new()
            gateway.state.last_heartbeat = 0
        end)

        it("should send heartbeat payload", function()
            local success, err = pcall(function()
                gateway:send_heartbeat()
            end)

            assert.is_true(success)
            assert.equals(1, #gateway.ws.messages)
            assert.equals(enums.HEARTBEAT, gateway.ws.messages[1].op)
        end)

        it("should track heartbeat time", function()
            local success, err = pcall(function()
                gateway:send_heartbeat()
            end)

            assert.is_true(success)
            assert.is_true(gateway.state.last_heartbeat > 0)
        end)
    end)

    describe("Send session description", function()
        local gateway

        before_each(function()
            gateway = VoiceGateway.new(mock_client, "guild123")
            gateway.ws = MockWebSocket.new()
            gateway.secret_key = {0, 1, 2, 3, 4, 5, 6, 7}
        end)

        it("should send session description payload", function()
            local success, err = pcall(function()
                gateway:send_session_description()
            end)

            assert.is_true(success)
            assert.equals(1, #gateway.ws.messages)
            assert.equals(enums.SESSION_DESCRIPTION, gateway.ws.messages[1].op)
            assert.is_table(gateway.ws.messages[1].d.secret)
        end)
    end)

    describe("Resume", function()
        local gateway

        before_each(function()
            gateway = VoiceGateway.new(mock_client, "guild123")
            gateway.ws = MockWebSocket.new()
            gateway.state.session_id = "session123"
            gateway.state.seq = 12345
        end)

        it("should send resume payload", function()
            local success, err = pcall(function()
                gateway:resume("session123", 12345)
            end)

            assert.is_true(success)
            assert.equals(1, #gateway.ws.messages)
            assert.equals(enums.RESUME, gateway.ws.messages[1].op)
        end)
    end)

    describe("Receive HELLO", function()
        local gateway

        before_each(function()
            gateway = VoiceGateway.new(mock_client, "guild123")
            gateway.ws = MockWebSocket.new()
        end)

        local hello_data = {
            heartbeat_interval = 5000,
            ssrc = 12345,
            ip = "10.0.0.1",
            port = 1337,
            modes = {"xsalsa20_poly1305_suffix"},
        }

        it("should handle HELLO event", function()
            local success, err = pcall(function()
                gateway:receive_hello(hello_data)
            end)

            assert.is_true(success)
            assert.equals(hello_data.heartbeat_interval, gateway.state.heartbeat_interval)
            assert.equals(hello_data.ssrc, gateway.state.ssrc)
            assert.equals(hello_data.ip, gateway.state.ip)
            assert.equals(hello_data.port, gateway.state.port)
        end)
    end)

    describe("Receive READY", function()
        local gateway

        before_each(function()
            gateway = VoiceGateway.new(mock_client, "guild123")
            gateway.ws = MockWebSocket.new()
        end)

        local ready_data = {
            seq = 12345,
            ssrc = 12345,
            ip = "10.0.0.1",
            port = 1337,
            modes = {"xsalsa20_poly1305_suffix"},
        }

        it("should handle READY event", function()
            local success, err = pcall(function()
                gateway:receive_ready(ready_data)
            end)

            assert.is_true(success)
        end)
    end)

    describe("Send client connect", function()
        local gateway

        before_each(function()
            gateway = VoiceGateway.new(mock_client, "guild123")
            gateway.ws = MockWebSocket.new()
        end)

        it("should send client connect event", function()
            local success, err = pcall(function()
                gateway:send_client_connect("user123", 54321)
            end)

            assert.is_true(success)
            assert.equals(1, #gateway.ws.messages)
            assert.equals(enums.CLIENT_CONNECT, gateway.ws.messages[1].op)
            assert.equals("user123", gateway.ws.messages[1].d.user_id)
            assert.equals(54321, gateway.ws.messages[1].d.ssrc)
        end)
    end)

    describe("Send client disconnect", function()
        local gateway

        before_each(function()
            gateway = VoiceGateway.new(mock_client, "guild123")
            gateway.ws = MockWebSocket.new()
        end)

        it("should send client disconnect event", function()
            local success, err = pcall(function()
                gateway:send_client_disconnect("user123", 54321)
            end)

            assert.is_true(success)
            assert.equals(1, #gateway.ws.messages)
            assert.equals(enums.CLIENT_DISCONNECT, gateway.ws.messages[1].op)
        end)
    end)

    describe("Send speaking", function()
        local gateway

        before_each(function()
            gateway = VoiceGateway.new(mock_client, "guild123")
            gateway.ws = MockWebSocket.new()
        end)

        it("should send speaking update", function()
            local success, err = pcall(function()
                gateway:send_speaking("user123", 54321, true)
            end)

            assert.is_true(success)
            assert.equals(1, #gateway.ws.messages)
            assert.equals(enums.SPEAKING, gateway.ws.messages[1].op)
            assert.equals(true, gateway.ws.messages[1].d.speaking)
        end)
    end)

    describe("Close", function()
        local gateway

        before_each(function()
            gateway = VoiceGateway.new(mock_client, "guild123")
        end)

        it("should close gateway", function()
            local success, err = pcall(function()
                gateway:close()
            end)

            assert.is_true(success)
            assert.is_true(gateway.state.connected == false)
        end)
    end)
end)
