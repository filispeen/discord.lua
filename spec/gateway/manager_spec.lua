-- spec/gateway/manager_spec.lua
-- Tests for shard manager

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
    },
    now = function() return 0 end
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

local ShardManager = require("gateway.manager")

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
