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
local json = require("dkjson")

-- Mock WebSocket. Real connections send JSON-encoded string frames (see
-- VoiceGateway:_send), so this decodes them back to tables for
-- assertions to keep existing test expectations intact.
local MockWebSocket = class("MockWebSocket")
function MockWebSocket.new()
    local self = {
        messages = {},
    }
    setmetatable(self, MockWebSocket)
    return self
end

function MockWebSocket:send(data)
    local decoded = data
    if type(data) == "string" then
        decoded = json.decode(data)
    end
    table.insert(self.messages, decoded)
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

    describe("Receive SESSION_DESCRIPTION", function()
        local gateway

        before_each(function()
            gateway = VoiceGateway.new(mock_client, "guild123")
            gateway.ws = MockWebSocket.new()
        end)

        local session_data = {
            mode = "xsalsa20_poly1305_suffix",
            secret_key = string.rep("k", 32),
        }

        it("should store the secret_key and mode", function()
            local success, err = pcall(function()
                gateway:receive_session_description(session_data)
            end)

            assert.is_true(success)
            assert.equals(session_data.secret_key, gateway.secret_key)
            assert.equals(session_data.mode, gateway.mode)
        end)

        it("should emit a session_description event", function()
            local received
            gateway:on("session_description", function(data)
                received = data
            end)

            gateway:receive_session_description(session_data)

            assert.is_not_nil(received)
            assert.equals(session_data.secret_key, received.secret_key)
            assert.equals(session_data.mode, received.mode)
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

    describe("Connect", function()
        local gateway
        local opened_ws
        local handlers

        before_each(function()
            handlers = {}
            opened_ws = MockWebSocket.new()
            opened_ws.on = function(_self, event, callback)
                handlers[event] = callback
            end
            package.loaded["coro-websocket"] = {
                connect = function(url)
                    opened_ws.url = url
                    return opened_ws
                end,
            }
            gateway = VoiceGateway.new(mock_client, "guild123")
        end)

        it("opens a wss url built from the raw endpoint host", function()
            gateway:connect("guildvoice.discord.gg:443", "tok", "sess1")
            assert.equals("wss://guildvoice.discord.gg/?v=8", opened_ws.url)
        end)

        it("strips a stray port with no scheme prefix", function()
            gateway:connect("guildvoice.discord.gg", "tok", "sess1")
            assert.equals("wss://guildvoice.discord.gg/?v=8", opened_ws.url)
        end)

        it("sends identify once the socket opens", function()
            gateway:connect("guildvoice.discord.gg", "tok", "sess1")
            handlers["open"]()

            assert.is_true(gateway.state.connected)
            assert.equals(1, #opened_ws.messages)
            assert.equals(enums.IDENTIFY, opened_ws.messages[1].op)
            assert.equals("tok", opened_ws.messages[1].d.token)
            assert.equals("sess1", opened_ws.messages[1].d.session_id)
        end)

        it("routes a HELLO frame to receive_hello and starts heartbeat", function()
            gateway:connect("guildvoice.discord.gg", "tok", "sess1")
            handlers["message"](json.encode({
                op = enums.HELLO,
                d = { heartbeat_interval = 5000, ssrc = 1, ip = "1.2.3.4", port = 4444, modes = {} },
            }))

            assert.equals(5000, gateway.state.heartbeat_interval)
            assert.equals(1, gateway.state.ssrc)
        end)

        it("routes a SESSION_DESCRIPTION frame to receive_session_description", function()
            gateway:connect("guildvoice.discord.gg", "tok", "sess1")
            handlers["message"](json.encode({
                op = enums.SESSION_DESCRIPTION,
                d = { secret_key = { 1, 2, 3 }, mode = "xsalsa20_poly1305_suffix" },
            }))

            assert.same({ 1, 2, 3 }, gateway.secret_key)
        end)

        it("routes CLIENT_CONNECT to the client_connect listener", function()
            gateway:connect("guildvoice.discord.gg", "tok", "sess1")
            local received
            gateway:on("client_connect", function(data)
                received = data
            end)
            handlers["message"](json.encode({
                op = enums.CLIENT_CONNECT,
                d = { user_id = "u1", ssrc = 99 },
            }))

            assert.is_not_nil(received)
            assert.equals("u1", received.user_id)
        end)

        it("routes SPEAKING to the speaking listener", function()
            gateway:connect("guildvoice.discord.gg", "tok", "sess1")
            local received
            gateway:on("speaking", function(data)
                received = data
            end)
            handlers["message"](json.encode({
                op = enums.SPEAKING,
                d = { user_id = "u1", ssrc = 99, speaking = true },
            }))

            assert.is_not_nil(received)
            assert.is_true(received.speaking)
        end)

        it("ignores malformed message frames instead of erroring", function()
            gateway:connect("guildvoice.discord.gg", "tok", "sess1")
            local success = pcall(function()
                handlers["message"]("not json")
            end)
            assert.is_true(success)
        end)

        it("marks disconnected and emits close on socket close", function()
            gateway:connect("guildvoice.discord.gg", "tok", "sess1")
            handlers["open"]()
            local closed
            gateway:on("close", function(data)
                closed = data
            end)
            handlers["close"](1000, "bye")

            assert.is_false(gateway.state.connected)
            assert.is_not_nil(closed)
            assert.equals(1000, closed.code)
        end)
    end)
end)
