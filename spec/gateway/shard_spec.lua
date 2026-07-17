-- spec/gateway/shard_spec.lua
-- Tests for shard connection

-- Setup package path to find lib modules
package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local class = require("core.class")

-- Mock luv for testing
local uv = {
    timer = {
        new = function()
            local timer = {
                start = function() end,
                stop = function() end,
            }
            return timer
        end
    }
}
package.loaded["luv"] = uv

-- Mock coro-websocket for testing
local mock_ws = {
    on = function() end,
    send = function() end,
    close = function() end,
}
package.loaded["coro-websocket"] = {
    connect = function()
        return mock_ws
    end,
}

local Shard = require("gateway.shard")

-- Mock HTTP client
local MockHTTPClient = class("MockHTTPClient")
function MockHTTPClient.new(token)
    local self = {
        token = token,
    }
    setmetatable(self, { __index = MockHTTPClient })
    return self
end

function MockHTTPClient:get(endpoint, callback)
    if endpoint == "/gateway/bot" then
        return {
            data = {
                shards = 3,
                heartbeat_interval = 5000,
                max_concurrency = 2,
            }
        }
    end
    return { data = { url = "wss://gateway.discord.gg" } }
end

describe("Shard", function()
    before_each(function()
        -- Reset state for tests
        Shard._state = {
            connected = false,
            heartbeat_interval = nil,
            last_heartbeat = 0,
            last_ack = 0,
            missed_acks = 0,
            session_id = nil,
            seq = 0,
        }
    end)

    it("should create a new shard", function()
        local mock_client = MockHTTPClient.new("test_token")
        local shard = Shard.new(mock_client, 0, 3)
        assert.equals(0, shard.shard_id)
        assert.equals(3, shard.total_shards)
        assert.is_true(shard._state.connected == false)
    end)

    it("should have listeners table", function()
        local mock_client = MockHTTPClient.new("test_token")
        local shard = Shard.new(mock_client, 0, 3)
        assert.is_table(shard.listeners)
    end)

    it("should return self on method calls", function()
        local mock_client = MockHTTPClient.new("test_token")
        local shard = Shard.new(mock_client, 0, 3)

        assert.equals(shard, shard:reset_state())
        assert.equals(shard, shard:connect())
        assert.equals(shard, shard:identify({token = "test"}))
        assert.equals(shard, shard:resume("session1", 123))
        assert.equals(shard, shard:send_heartbeat())
        assert.equals(shard, shard:close())
    end)

    it("should have connect method", function()
        local mock_client = MockHTTPClient.new("test_token")
        local shard = Shard.new(mock_client, 0, 3)

        -- Verify the method exists and is callable
        assert.equals("function", type(shard.connect))
    end)

    it("should dispatch ready event", function()
        local mock_client = MockHTTPClient.new("test_token")
        local shard = Shard.new(mock_client, 0, 3)

        -- READY is a DISPATCH (op 0) event with t == "READY", not its own opcode
        local ready_event = { op = 0, t = "READY", s = 1, d = { session_id = "sess1" } }
        shard:dispatch(ready_event)

        -- Verify seq was updated
        assert.equals(1, shard._state.seq)
        assert.is_true(shard._state.connected)
        assert.equals("sess1", shard._state.session_id)
    end)

    it("should start heartbeating after HELLO", function()
        local mock_client = MockHTTPClient.new("test_token")
        local shard = Shard.new(mock_client, 0, 3)

        local hello_event = { op = 10, d = { heartbeat_interval = 41250 } }
        shard:dispatch(hello_event)

        assert.equals(41250, shard._state.heartbeat_interval)
    end)

    it("should forward dispatch events by event name", function()
        local mock_client = MockHTTPClient.new("test_token")
        local shard = Shard.new(mock_client, 0, 3)

        local received = nil
        shard:on_event("MESSAGE_CREATE", function(d) received = d end)

        shard:dispatch({ op = 0, t = "MESSAGE_CREATE", s = 2, d = { content = "hello" } })

        assert.is_not_nil(received)
        assert.equals("hello", received.content)
    end)

    it("should call on_ready listeners when READY dispatches", function()
        local mock_client = MockHTTPClient.new("test_token")
        local shard = Shard.new(mock_client, 0, 3)

        local fired = false
        shard:on_ready(function() fired = true end)

        shard:dispatch({ op = 0, t = "READY", s = 1, d = {} })

        assert.is_true(fired)
    end)

    it("should track heartbeat", function()
        local mock_client = MockHTTPClient.new("test_token")
        local shard = Shard.new(mock_client, 0, 3)

        shard:send_heartbeat()

        assert.is_true(shard._state.last_heartbeat > 0)
    end)

    it("should reset state", function()
        local mock_client = MockHTTPClient.new("test_token")
        local shard = Shard.new(mock_client, 0, 3)

        shard._state.connected = true
        shard._state.seq = 999

        shard:reset_state()

        assert.is_false(shard._state.connected)
        assert.equals(0, shard._state.seq)
    end)

    it("should assign self.ws on connect so send/close are not silent no-ops", function()
        -- Regression test: connect() previously only bound listeners to a local
        -- ws variable and never assigned self.ws, so Shard:send and Shard:close
        -- silently did nothing for the lifetime of the shard.
        local mock_client = MockHTTPClient.new("test_token")
        local shard = Shard.new(mock_client, 0, 3)

        shard:connect()

        assert.is_not_nil(shard.ws)
    end)

    it("should actually deliver identify through send after self.ws is set", function()
        local sent = {}
        local local_mock_ws = {
            on = function() end,
            send = function(_self, data) table.insert(sent, data) end,
            close = function() end,
        }
        package.loaded["coro-websocket"] = {
            connect = function() return local_mock_ws end,
        }
        package.loaded["gateway.shard"] = nil
        local FreshShard = require("gateway.shard")

        local mock_client = MockHTTPClient.new("test_token")
        local shard = FreshShard.new(mock_client, 0, 3)
        shard:connect()
        shard:identify({ token = "test_token" })

        assert.equals(1, #sent)

        -- restore the shared mock for any tests that run after this one
        package.loaded["coro-websocket"] = {
            connect = function() return mock_ws end,
        }
        package.loaded["gateway.shard"] = nil
    end)
end)
