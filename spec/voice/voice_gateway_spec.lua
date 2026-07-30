-- spec/voice/voice_gateway_spec.lua
-- Tests for voice gateway

require("spec_helper")
package.path = "spec/voice/?.lua;" .. package.path

-- Mock luv for testing
local created_timers = {}
local mock_luv = {
    new_timer = function()
        local timer = {
            started = false,
            stopped = false,
            start = function(self, interval, repeat_interval, callback)
                self.started = true
                self.interval = interval
                self.repeat_interval = repeat_interval
                self.callback = callback
            end,
            stop = function(self)
                self.stopped = true
            end,
        }
        table.insert(created_timers, timer)
        return timer
    end,
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

local class = require("./core/class")
local enums = require("./voice/enums")
local errors = require("./voice/errors")
local json = require("deps/json")

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

function MockWebSocket:start_reading()
    return true
end


local VoiceGateway = require("./voice/voice_gateway")

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

        -- Discord's real voice gateway HELLO (op 8) only ever carries
        -- heartbeat_interval, unlike ssrc/ip/port/modes which only arrive
        -- later on READY (op 2).
        local hello_data = {
            heartbeat_interval = 5000,
        }

        it("should handle HELLO event", function()
            local success, err = pcall(function()
                gateway:receive_hello(hello_data)
            end)

            assert.is_true(success)
            assert.equals(hello_data.heartbeat_interval, gateway.state.heartbeat_interval)
        end)

        it("does not emit ready from HELLO alone, only READY does that", function()
            local received = false
            gateway:on("ready", function()
                received = true
            end)

            gateway:receive_hello(hello_data)

            assert.is_false(received)
        end)
    end)

    describe("Heartbeat timer", function()
        local gateway

        before_each(function()
            created_timers = {}
            gateway = VoiceGateway.new(mock_client, "guild123")
            gateway.ws = MockWebSocket.new()
        end)

        it("starts a real timer on HELLO with the given interval", function()
            gateway:receive_hello({ heartbeat_interval = 5000 })

            assert.equals(1, #created_timers)
            assert.is_true(created_timers[1].started)
            assert.equals(5000, created_timers[1].interval)
            assert.equals(5000, created_timers[1].repeat_interval)
            assert.equals(gateway.state.heartbeat_timer, created_timers[1])
        end)

        it("sends a heartbeat when the timer fires", function()
            gateway:receive_hello({ heartbeat_interval = 5000 })
            local timer = created_timers[1]

            assert.equals(0, #gateway.ws.messages)
            timer.callback()

            assert.equals(1, #gateway.ws.messages)
            assert.equals(enums.HEARTBEAT, gateway.ws.messages[1].op)
        end)

        it("stops the previous timer when a new HELLO restarts the heartbeat", function()
            gateway:receive_hello({ heartbeat_interval = 5000 })
            local first_timer = created_timers[1]

            gateway:receive_hello({ heartbeat_interval = 6000 })

            assert.is_true(first_timer.stopped)
            assert.equals(2, #created_timers)
            assert.equals(6000, created_timers[2].interval)
        end)

        it("stops the timer on close", function()
            gateway:receive_hello({ heartbeat_interval = 5000 })
            local timer = created_timers[1]

            gateway:close()

            assert.is_true(timer.stopped)
            assert.is_nil(gateway.state.heartbeat_timer)
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
                -- Production code registers listeners the same way
                -- gateway.Shard does: ws:on(event, function(_, ...) ... end),
                -- since core.emitter passes the emitter itself as the first
                -- callback argument. Wrapping here lets every existing
                -- handlers[event](...) call in this describe block keep
                -- passing only the real payload args.
                handlers[event] = function(...)
                    return callback(opened_ws, ...)
                end
            end
            -- VoiceGateway:connect now goes through parseUrl -> connect ->
            -- gateway.ws_adapter.wrap (mirrors gateway.Shard:connect), so
            -- the fake here plugs into that same seam: parseUrl just
            -- passes the url through, connect returns a dummy (res, read,
            -- write) triple, and ws_adapter.wrap is stubbed to hand back
            -- opened_ws directly instead of building a real coroutine
            -- EventEmitter, keeping every existing handlers[event](...)
            -- assertion in this describe block unchanged.
            package.loaded["coro-websocket"] = {
                parseUrl = function(url)
                    return { url = url }
                end,
                connect = function(options)
                    opened_ws.url = options.url
                    return {}, function() end, function() end
                end,
            }
            package.loaded["../gateway/ws_adapter"] = {
                wrap = function(_res, _read, _write)
                    return opened_ws
                end,
            }
            gateway = VoiceGateway.new(mock_client, "guild123")
        end)

        after_each(function()
            package.loaded["../gateway/ws_adapter"] = nil
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
                d = { heartbeat_interval = 5000 },
            }))

            assert.equals(5000, gateway.state.heartbeat_interval)
        end)

        it("routes a READY frame to receive_ready and emits ready with ssrc/ip/port/modes", function()
            gateway:connect("guildvoice.discord.gg", "tok", "sess1")
            local received
            gateway:on("ready", function(data)
                received = data
            end)
            handlers["message"](json.encode({
                op = enums.READY,
                d = { ssrc = 1, ip = "1.2.3.4", port = 4444, modes = { "xsalsa20_poly1305_suffix" } },
            }))

            assert.is_not_nil(received)
            assert.equals(1, received.ssrc)
            assert.equals("1.2.3.4", received.ip)
            assert.equals(4444, received.port)
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

    describe("Reconnect", function()
        local gateway
        local sockets
        local handler_list

        local function fire_reconnect_timer()
            local timer = created_timers[#created_timers]
            timer.callback()
        end

        before_each(function()
            sockets = {}
            handler_list = {}
            -- Same seam as the "Connect" describe block above: fake
            -- parseUrl/connect just pass the url through, and
            -- gateway.ws_adapter.wrap is stubbed to return a fresh
            -- MockWebSocket per connect() call so reconnects create a new
            -- "socket" entry the same way the old direct-connect mock did.
            package.loaded["coro-websocket"] = {
                parseUrl = function(url)
                    return { url = url }
                end,
                connect = function(options)
                    return { url = options.url }, function() end, function() end
                end,
            }
            package.loaded["../gateway/ws_adapter"] = {
                wrap = function(res, _read, _write)
                    local ws = MockWebSocket.new()
                    ws.url = res.url
                    local handlers = {}
                    ws.on = function(_self, event, callback)
                        -- Same emitter-shape wrapping as the "Connect"
                        -- describe block above.
                        handlers[event] = function(...)
                            return callback(ws, ...)
                        end
                    end
                    table.insert(sockets, ws)
                    table.insert(handler_list, handlers)
                    return ws
                end,
            }
            gateway = VoiceGateway.new(mock_client, "guild123")
        end)

        after_each(function()
            package.loaded["../gateway/ws_adapter"] = nil
        end)

        it("does not reconnect on a clean close (code 1000)", function()
            gateway:connect("guildvoice.discord.gg", "tok", "sess1")
            handler_list[1]["open"]()
            handler_list[1]["close"](1000, "bye")

            assert.equals(1, #sockets)
        end)

        it("does not reconnect after an explicit close()", function()
            gateway:connect("guildvoice.discord.gg", "tok", "sess1")
            handler_list[1]["open"]()
            gateway:close()

            assert.equals(1, #sockets)
        end)

        it("schedules a reopen (after backoff) on a plain non-1000 close", function()
            gateway:connect("guildvoice.discord.gg", "tok", "sess1")
            handler_list[1]["open"]()
            handler_list[1]["close"](1006, "abnormal closure")

            assert.equals(1, #sockets)
            fire_reconnect_timer()

            assert.equals(2, #sockets)
            assert.equals("wss://guildvoice.discord.gg/?v=8", sockets[2].url)
        end)

        it("preserves session_id/token/seq across a resumable reconnect", function()
            gateway:connect("guildvoice.discord.gg", "tok", "sess1")
            handler_list[1]["open"]()
            handler_list[1]["message"](json.encode({
                op = enums.HELLO,
                d = { heartbeat_interval = 5000, ssrc = 1, ip = "1.2.3.4", port = 4444, modes = {} },
                seq = 7,
            }))
            handler_list[1]["close"](1006, "abnormal closure")

            assert.equals("sess1", gateway.state.session_id)
            assert.equals("tok", gateway.state.token)
            assert.equals(7, gateway.state.seq)
        end)

        it("sends RESUME instead of IDENTIFY once the reopened socket opens", function()
            gateway:connect("guildvoice.discord.gg", "tok", "sess1")
            handler_list[1]["open"]()
            handler_list[1]["close"](1006, "abnormal closure")
            fire_reconnect_timer()
            handler_list[2]["open"]()

            assert.equals(1, #sockets[2].messages)
            assert.equals(enums.RESUME, sockets[2].messages[1].op)
            assert.equals("sess1", sockets[2].messages[1].d.session_id)
        end)

        it("emits a reconnecting event with the preserved session_id and attempt number", function()
            gateway:connect("guildvoice.discord.gg", "tok", "sess1")
            handler_list[1]["open"]()
            local received
            gateway:on("reconnecting", function(data)
                received = data
            end)
            handler_list[1]["close"](1006, "abnormal closure")

            assert.is_not_nil(received)
            assert.equals("sess1", received.session_id)
            assert.equals(1, received.attempt)
        end)

        it("goes back to IDENTIFY on the next fresh connect() after RESUMED", function()
            gateway:connect("guildvoice.discord.gg", "tok", "sess1")
            handler_list[1]["open"]()
            handler_list[1]["close"](1006, "abnormal closure")
            fire_reconnect_timer()
            handler_list[2]["open"]()
            handler_list[2]["message"](json.encode({ op = enums.RESUMED, d = {} }))

            gateway:connect("guildvoice.discord.gg", "tok", "sess2")
            handler_list[3]["open"]()

            assert.equals(enums.IDENTIFY, sockets[3].messages[1].op)
        end)

        it("does not reconnect when session_id/token/endpoint are missing", function()
            gateway.state.token = "tok"
            gateway.state.session_id = "sess1"
            gateway.state.endpoint = nil
            gateway:_trigger_reconnect()

            assert.equals(0, #sockets)
        end)

        it("resets reconnect_attempts to 0 after RESUMED", function()
            gateway:connect("guildvoice.discord.gg", "tok", "sess1")
            handler_list[1]["open"]()
            handler_list[1]["close"](1006, "abnormal closure")
            fire_reconnect_timer()
            handler_list[2]["open"]()
            handler_list[2]["message"](json.encode({ op = enums.RESUMED, d = {} }))

            assert.equals(0, gateway.reconnect_attempts)
        end)

        it("gives up after MAX_RECONNECT_ATTEMPTS with reconnect_failed", function()
            gateway:connect("guildvoice.discord.gg", "tok", "sess1")
            handler_list[1]["open"]()

            local failed
            gateway:on("reconnect_failed", function(data)
                failed = data
            end)

            for i = 1, 5 do
                handler_list[i]["close"](1006, "abnormal closure")
                fire_reconnect_timer()
                handler_list[i + 1]["open"]()
            end
            handler_list[6]["close"](1006, "abnormal closure")

            assert.is_not_nil(failed)
            assert.equals("max_attempts_exceeded", failed.reason)
            assert.equals(0, gateway.reconnect_attempts)
        end)

        it("invalidates the session on CLOSE_SESSION_NO_LONGER_VALID (4006) instead of resuming", function()
            gateway:connect("guildvoice.discord.gg", "tok", "sess1")
            handler_list[1]["open"]()

            local invalidated
            gateway:on("session_invalidated", function(data)
                invalidated = data
            end)
            handler_list[1]["close"](enums.CLOSE_SESSION_NO_LONGER_VALID, "session no longer valid")

            assert.is_not_nil(invalidated)
            assert.equals(enums.CLOSE_SESSION_NO_LONGER_VALID, invalidated.code)
            assert.is_nil(gateway.state.session_id)
            assert.is_nil(gateway.state.token)
            assert.equals(0, gateway.state.seq)
            assert.equals(1, #sockets)
        end)

        it("invalidates the session on CLOSE_SESSION_TIMEOUT (4009) instead of resuming", function()
            gateway:connect("guildvoice.discord.gg", "tok", "sess1")
            handler_list[1]["open"]()
            handler_list[1]["close"](enums.CLOSE_SESSION_TIMEOUT, "session timeout")

            assert.is_nil(gateway.state.session_id)
            assert.equals(1, #sockets)
        end)

        it("gives up immediately on a fatal close code (4014) without reconnecting", function()
            gateway:connect("guildvoice.discord.gg", "tok", "sess1")
            handler_list[1]["open"]()

            local failed
            gateway:on("reconnect_failed", function(data)
                failed = data
            end)
            handler_list[1]["close"](enums.CLOSE_DISCONNECTED, "disconnected")

            assert.is_not_nil(failed)
            assert.equals("fatal_close_code", failed.reason)
            assert.equals(1, #sockets)
        end)
    end)
end)
