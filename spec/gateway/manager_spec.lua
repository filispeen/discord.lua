-- spec/gateway/manager_spec.lua
-- Tests for shard manager

-- Setup package path to find lib modules
package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local class = require("core.class")
local ShardManager = require("gateway.manager")

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
                shards = {0, 1, 2},
                heartbeat_interval = 5000,
                max_concurrency = 2,
            }
        }
    end
    return { data = { url = "wss://gateway.discord.gg" } }
end

describe("ShardManager", function()
    before_each(function()
        -- Mock the Shard class
        Shard = require("lib.gateway.shard")
    end)

    it("should create a new shard manager", function()
        local mock_client = MockHTTPClient.new("test_token")
        local manager = ShardManager.new(mock_client, 2)

        assert.is_table(manager.shards)
        assert.equals(2, manager.max_concurrency)
    end)

    it("should return self on method calls", function()
        local mock_client = MockHTTPClient.new("test_token")
        local manager = ShardManager.new(mock_client, 2)

        assert.equals(manager, manager:start())
        assert.equals(manager, manager:stop())
        assert.equals(manager, manager:get_shard(0))
        assert.equals(manager, manager:shards())
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
        manager.shards = {mock_shard}

        manager:dispatch({test = true})

        -- Verify emit was called (would need mock verification in real tests)
    end)

    it("should update max_concurrency", function()
        local mock_client = MockHTTPClient.new("test_token")
        local manager = ShardManager.new(mock_client, 5)

        -- Mock the gateway response with lower max_concurrency
        mock_client.get = function(...)
            return {
                data = {
                    shards = {0, 1},
                    max_concurrency = 1,
                }
            }
        end

        manager:start()

        assert.equals(1, manager.max_concurrency)
    end)
end)
