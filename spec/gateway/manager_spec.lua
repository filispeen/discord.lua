-- spec/gateway/manager_spec.lua
-- Tests for shard manager

-- Setup package path to find lib modules
require("spec_helper")

local class = require("./core/class")
local timer_callbacks = {}

-- Mock luv for testing
local uv = {
    new_timer = function()
        local timer
        timer = {
            closing = false,
            start = function(_, _, _, callback) timer_callbacks[#timer_callbacks + 1] = callback end,
            stop = function() end,
            close = function(self)
                if self.closing then error("handle is already closing") end
                self.closing = true
            end,
        }
        return timer
    end,
    timer = {
        new = function()
            local timer = {
                start = function() end,
                stop = function() end,
                close = function() end,
            }
            return timer
        end
    },
    now = function() return 0 end,
    is_closing = function(timer) return timer.closing end,
}
package.loaded["luv"] = uv

-- Mock coro-websocket for testing
local function mock_read() return nil end
local function mock_write() end
package.loaded["coro-websocket"] = {
    connect = function()
        return {}, mock_read, mock_write
    end,
    parseUrl = function(url)
        return { host = "gateway.discord.gg", port = 443, tls = true, pathname = url }
    end,
}

local ShardManager = require("./gateway/manager")

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

describe("ShardManager", function()
    it("should create a new shard manager", function()
        local mock_client = MockHTTPClient.new("test_token")
        local manager = ShardManager.new(mock_client, 2)

        assert.is_table(manager:shards())
        assert.equals(2, manager.max_concurrency)
    end)

    it("should return self on method calls", function()
        local mock_client = MockHTTPClient.new("test_token")
        local manager = ShardManager.new(mock_client, 2)

        assert.equals(manager, manager:start())
        assert.equals(manager, manager:stop())
        assert.equals(manager, manager:dispatch({}))
    end)

    it("should get shards", function()
        local mock_client = MockHTTPClient.new("test_token")
        local manager = ShardManager.new(mock_client, 2)

        local shards = manager:shards()
        assert.is_table(shards)
    end)

    it("should get shard by ID", function()
        local mock_client = MockHTTPClient.new("test_token")
        local manager = ShardManager.new(mock_client, 2)

        local shard = manager:get_shard(0)
        assert.is_nil(shard) -- Shards not created until start()
    end)

    it("should have start method", function()
        local mock_client = MockHTTPClient.new("test_token")
        local manager = ShardManager.new(mock_client, 2)

        -- Verify the method exists and is callable
        assert.equals("function", type(manager.start))
    end)

    it("should have stop method", function()
        local mock_client = MockHTTPClient.new("test_token")
        local manager = ShardManager.new(mock_client, 2)

        -- Verify the method exists and is callable
        assert.equals("function", type(manager.stop))
    end)

    it("should dispatch events to shards", function()
        local mock_client = MockHTTPClient.new("test_token")
        local manager = ShardManager.new(mock_client, 2)

        local mock_shard = {
            emit = function(self, event)
                -- Mock emit
            end
        }
        manager._shards = {mock_shard}

        manager:dispatch({test = true})

        -- Verify emit was called (would need mock verification in real tests)
    end)

    it("should update max_concurrency", function()
        local mock_client = MockHTTPClient.new("test_token")
        local manager = ShardManager.new(mock_client, 5)

        -- Mock the gateway response with lower max_concurrency
        mock_client.get = function(...)
            return {
                url = "wss://gateway.discord.gg",
                shards = 2,
                session_start_limit = {
                    max_concurrency = 1,
                },
            }
        end

        manager:start()

        assert.equals(1, manager.max_concurrency)
    end)

    it("queues five shards by identify bucket at concurrency one and two", function()
        local Shard = require("./gateway/shard")
        local original_connect = Shard.connect
        local starts = {}
        Shard.connect = function(shard)
            starts[#starts + 1] = shard.shard_id
            shard._state.connected = true
            return shard
        end
        local function check(concurrency, expected)
            starts = {}
            local client = MockHTTPClient.new("test_token")
            client.get = function()
                return { shards = 5, session_start_limit = { max_concurrency = concurrency } }
            end
            local manager = ShardManager.new(client, concurrency)
            manager:start()
            assert.same(expected, starts)
            assert.equals(5, #manager._state.queues[0] + (manager._state.queues[1] and #manager._state.queues[1] or 0))
            manager:stop()
        end
        check(1, { 0 })
        check(2, { 0, 1 })
        Shard.connect = original_connect
    end)

    it("connects each bucket shard inside a coroutine and advances after failure", function()
        local Shard = require("./gateway/shard")
        local original_connect = Shard.connect
        local starts = {}
        timer_callbacks = {}
        Shard.connect = function(shard)
            if coroutine.running() == nil then error("connect outside coroutine") end
            starts[#starts + 1] = shard.shard_id
            if shard.shard_id == 0 then error("connect failed") end
            return shard
        end
        local function check(concurrency, initial, after_failure)
            starts = {}
            timer_callbacks = {}
            local client = MockHTTPClient.new("test_token")
            client.get = function()
                return { shards = 5, session_start_limit = { max_concurrency = concurrency } }
            end
            local manager = ShardManager.new(client, concurrency)
            local received
            manager:on_shard_error(0, function(_, _, err) received = err end)
            manager:start()
            assert.same(initial, starts)
            assert.is_truthy(tostring(received):find("connect failed", 1, true))
            timer_callbacks[#timer_callbacks]()
            assert.same(after_failure, starts)
            manager:stop()
        end
        check(1, { 0 }, { 0, 1 })
        check(2, { 0, 1 }, { 0, 1, 2 })
        Shard.connect = original_connect
    end)

    it("should forward a dispatch payload to on_dispatch listeners by event name", function()
        local mock_client = MockHTTPClient.new("test_token")
        local manager = ShardManager.new(mock_client, 2)

        local received = nil
        manager:on_dispatch("MESSAGE_CREATE", function(d) received = d end)

        manager:_forward_dispatch({ t = "MESSAGE_CREATE", d = { content = "hi" } })

        assert.is_not_nil(received)
        assert.equals("hi", received.content)
    end)

    it("should ignore a dispatch payload with no matching listener", function()
        local mock_client = MockHTTPClient.new("test_token")
        local manager = ShardManager.new(mock_client, 2)

        -- Should not error even though nothing is subscribed
        manager:_forward_dispatch({ t = "GUILD_CREATE", d = {} })
    end)

    it("should wire shards created in start() to forward dispatch events", function()
        local mock_client = MockHTTPClient.new("test_token")
        mock_client.get = function(...)
            return {
                url = "wss://gateway.discord.gg",
                shards = 1,
                session_start_limit = { max_concurrency = 1 },
            }
        end

        local manager = ShardManager.new(mock_client, 1)
        manager:start()

        local received = nil
        manager:on_dispatch("MESSAGE_CREATE", function(d) received = d end)

        local shard = manager:get_shard(0)
        shard:dispatch({ op = 0, t = "MESSAGE_CREATE", s = 1, d = { content = "wired" } })

        assert.is_not_nil(received)
        assert.equals("wired", received.content)
    end)

    it("fires on_ready once every started shard has dispatched READY", function()
        local mock_client = MockHTTPClient.new("test_token")
        mock_client.get = function(...)
            return {
                url = "wss://gateway.discord.gg",
                shards = 1,
                session_start_limit = { max_concurrency = 1 },
            }
        end

        local manager = ShardManager.new(mock_client, 1)

        local ready_payload_received = nil
        manager:on_ready(function(ready_payload)
            ready_payload_received = ready_payload
        end)

        manager:start()

        local shard = manager:get_shard(0)
        shard:dispatch({
            op = 0,
            t = "READY",
            s = 1,
            d = { session_id = "abc", user = { id = "1", username = "TestBot" } },
        })

        assert.is_not_nil(ready_payload_received)
        assert.equals("TestBot", ready_payload_received.user.username)
    end)

    it("fires on_shard_ready with the shard id and READY payload", function()
        local mock_client = MockHTTPClient.new("test_token")
        mock_client.get = function(...)
            return {
                url = "wss://gateway.discord.gg",
                shards = 1,
                session_start_limit = { max_concurrency = 1 },
            }
        end

        local manager = ShardManager.new(mock_client, 1)

        local received_shard_id = nil
        manager:on_shard_ready(0, function(shard_id, _shard, ready_payload)
            received_shard_id = shard_id
        end)

        manager:start()

        local shard = manager:get_shard(0)
        shard:dispatch({ op = 0, t = "READY", s = 1, d = { session_id = "abc" } })

        assert.equals(0, received_shard_id)
    end)

    it("forwards shard error and disconnect arguments", function()
        local client = MockHTTPClient.new("test_token")
        client.get = function()
            return { shards = 1, session_start_limit = { max_concurrency = 1 } }
        end
        local manager = ShardManager.new(client, 1)
        local error_args
        local disconnect_args
        manager:on_shard_error(0, function(...) error_args = { ... } end)
        manager:on_shard_disconnect(0, function(...) disconnect_args = { ... } end)
        manager:start()
        local shard = manager:get_shard(0)
        local err = { message = "failure" }
        local event = { code = 1006 }
        shard:emit("error", err)
        shard:emit("disconnect", event)
        assert.equals(0, error_args[1])
        assert.equals(shard, error_args[2])
        assert.equals(err, error_args[3])
        assert.equals(event, disconnect_args[3])
        manager:stop()
    end)

    it("wait_for_shard resumes when the shard becomes ready", function()
        local manager = ShardManager.new(MockHTTPClient.new("test_token"), 1)
        local shard = { _state = { connected = false } }
        manager._shards[0] = shard
        local result
        local thread = coroutine.create(function() result = manager:wait_for_shard(0, 1000) end)
        assert.is_true(coroutine.resume(thread))
        shard._state.connected = true
        timer_callbacks[#timer_callbacks]()
        assert.is_true(result)
    end)

    it("stops shards when its timer list contains a closed handle", function()
        local manager = ShardManager.new(MockHTTPClient.new("test_token"), 1)
        local closed = uv.new_timer()
        closed:close()
        local live = uv.new_timer()
        local shard_closed = false
        manager._state = { timers = { closed, live } }
        manager._shards = { { close = function() shard_closed = true end } }
        manager:stop()
        assert.is_true(live.closing)
        assert.is_true(shard_closed)
    end)

    it("guild_shard_id returns 0 for a single shard", function()
        local mock_client = MockHTTPClient.new("test_token")
        local manager = ShardManager.new(mock_client, 1)
        manager:start()

        assert.equals(0, manager:guild_shard_id("881207955029110855"))
    end)

    it("guild_shard_id distributes guilds across shards using Discord's formula", function()
        local mock_client = MockHTTPClient.new("test_token")
        mock_client.get = function(...)
            return {
                url = "wss://gateway.discord.gg",
                shards = 4,
                session_start_limit = { max_concurrency = 4 },
            }
        end

        local manager = ShardManager.new(mock_client, 4)
        manager:start()

        local guild_id = "881207955029110855"
        local expected = math.floor(tonumber(guild_id) / 4194304) % 4

        assert.equals(expected, manager:guild_shard_id(guild_id))
    end)

    it("get_shard_for_guild returns the shard object for that guild's shard id", function()
        local mock_client = MockHTTPClient.new("test_token")
        local manager = ShardManager.new(mock_client, 1)
        manager:start()

        local shard = manager:get_shard_for_guild("881207955029110855")

        assert.equals(manager:get_shard(0), shard)
    end)

    it("voice_state_update sends opcode 4 through the guild's shard", function()
        local mock_client = MockHTTPClient.new("test_token")
        local manager = ShardManager.new(mock_client, 1)
        manager:start()

        local shard = manager:get_shard(0)
        local sent = nil
        shard.ws = {
            send = function(_self, raw)
                sent = raw
            end,
        }

        local ok = manager:voice_state_update("111", "222", false, true)

        assert.is_true(ok)
        assert.is_not_nil(sent)
        assert.is_not_nil(sent:find("\"op\":4"))
    end)

    it("voice_state_update returns false when no shard is available", function()
        local mock_client = MockHTTPClient.new("test_token")
        local manager = ShardManager.new(mock_client, 1)

        local ok, err = manager:voice_state_update("111", "222")

        assert.is_false(ok)
        assert.is_not_nil(err)
    end)
end)
