-- spec/gateway/shard_spec.lua
-- Tests for shard connection

-- Setup package path to find lib modules
package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local class = require("core.class")

-- Mock luv for testing
local uv = {
    new_timer = function()
        local timer = {
            start = function() end,
            stop = function() end,
        }
        return timer
    end
}
package.loaded["luv"] = uv

-- Mock coro-websocket for testing
local function mock_parse_url(url)
    return { host = "gateway.discord.gg", port = 443, tls = true, pathname = url }
end
local function mock_read() return nil end
local function mock_write() end
package.loaded["coro-websocket"] = {
    connect = function()
        return {}, mock_read, mock_write
    end,
    parseUrl = mock_parse_url,
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
            url = "wss://gateway.discord.gg",
            shards = 3,
            session_start_limit = {
                total = 1000,
                remaining = 999,
                reset_after = 0,
                max_concurrency = 2,
            },
        }
    end
    return { url = "wss://gateway.discord.gg" }
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
        --
        -- Uses a blocking mock_read (like the identify test below) so the
        -- ws_adapter reading coroutine does not immediately observe a closed
        -- connection and tear self.ws back down via Shard:close before this
        -- assertion runs.
        local function blocking_read() coroutine.yield() end
        local function noop_write() end
        package.loaded["coro-websocket"] = {
            connect = function() return {}, blocking_read, noop_write end,
            parseUrl = mock_parse_url,
        }
        package.loaded["gateway.shard"] = nil
        local FreshShard = require("gateway.shard")

        local mock_client = MockHTTPClient.new("test_token")
        local shard = FreshShard.new(mock_client, 0, 3)

        shard:connect()

        assert.is_not_nil(shard.ws)

        -- restore the shared mock for any tests that run after this one
        package.loaded["coro-websocket"] = {
            connect = function() return {}, mock_read, mock_write end,
            parseUrl = mock_parse_url,
        }
        package.loaded["gateway.shard"] = nil
    end)

    it("voice_state_update serializes channel_id=nil as JSON null, not an omitted field", function()
        -- Discord's VOICE_STATE_UPDATE payload requires channel_id to be
        -- present and explicitly null to signal "leave voice channel".
        -- Lua drops table keys whose value is nil, so if the payload were
        -- built with channel_id = nil directly (instead of json.null),
        -- the field would be missing entirely from the encoded JSON,
        -- which is what caused Discord to close the whole gateway
        -- connection instead of just processing the leave.
        local sent = {}
        local function mock_read() coroutine.yield() end
        local function mock_write(message)
            if message then
                table.insert(sent, message.payload)
            end
        end
        package.loaded["coro-websocket"] = {
            connect = function() return {}, mock_read, mock_write end,
            parseUrl = mock_parse_url,
        }
        package.loaded["gateway.shard"] = nil
        local FreshShard = require("gateway.shard")
        local json = require("core.json_compat")

        local mock_client = MockHTTPClient.new("test_token")
        local shard = FreshShard.new(mock_client, 0, 3)
        shard:connect()
        shard:voice_state_update("guild123", nil, false, false)

        assert.equals(1, #sent)
        local decoded = json.decode(sent[1])
        assert.is_true(decoded.d.channel_id == nil or decoded.d.channel_id == json.null)
        assert.is_true(sent[1]:find('"channel_id":null', 1, true) ~= nil)

        package.loaded["coro-websocket"] = {
            connect = function() return {}, mock_read, mock_write end,
            parseUrl = mock_parse_url,
        }
        package.loaded["gateway.shard"] = nil
    end)

    it("should actually deliver identify through send after self.ws is set", function()
        local sent = {}
        -- Blocks forever, simulating a real coro-http read() that only
        -- resumes on the libuv event loop. Prevents the ws_adapter's
        -- reading coroutine from closing the socket before identify runs.
        local function mock_read() coroutine.yield() end
        local function mock_write(message)
            if message then
                table.insert(sent, message.payload)
            end
        end
        package.loaded["coro-websocket"] = {
            connect = function() return {}, mock_read, mock_write end,
            parseUrl = mock_parse_url,
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
            connect = function() return {}, mock_read, mock_write end,
            parseUrl = mock_parse_url,
        }
        package.loaded["gateway.shard"] = nil
    end)
end)
