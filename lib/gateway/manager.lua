-- lib/gateway/manager.lua
-- Shard manager for multiple WebSocket connections
--
-- Public Contract:
--   ShardManager.new(client, max_concurrency) -> ShardManager
--     Creates a new ShardManager.
--
--   ShardManager:start() -> nil
--     Starts all shards.
--
--   ShardManager:stop() -> nil
--     Stops all shards.
--
--   ShardManager:get_shard(id) -> Shard or nil
--     Gets a shard by ID.
--
--   ShardManager:shards() -> table
--     Gets all shards.
--
--   ShardManager:dispatch(event) -> nil
--     Dispatches an event to all shards.
--
--   ShardManager:on_ready(callback) -> self
--     Listen for bot ready event.

local class = require("core.class")
local Shard = require("gateway.shard")
local uv = package.loaded["mock_luv"] or require("luv")

-- ShardManager class
local ShardManager = class("ShardManager")

-- Internal state
ShardManager._state = {
    shards = {},
    max_concurrency = 1,
    ready_event = nil,
}

-- Create a new ShardManager
function ShardManager.new(client, max_concurrency)
    local self = {
        client = client,
        max_concurrency = max_concurrency or 1,
        shards = {},
        listeners = {},
    }
    setmetatable(self, { __index = ShardManager })
    return self
end

-- Start all shards
function ShardManager:start()
    -- Get shard configuration from gateway
    local gateway_url = self.client:get("/gateway/bot")
    if not gateway_url then
        return self
    end

    -- Parse shard count and max concurrency
    local shards = gateway_url.data.shards
    local max_concurrency = gateway_url.data.max_concurrency or 1

    -- Update max concurrency
    self.max_concurrency = math.min(self.max_concurrency, max_concurrency)

    -- Create shards
    for i = 1, #shards do
        local shard_id = i - 1
        self.shards[shard_id] = Shard.new(self.client, shard_id, #shards)
    end

    -- Start each shard
    for _, shard in ipairs(self.shards) do
        shard:connect()

        -- Wait for shard to be ready (for max_concurrency control)
        local shard_ready = false
        shard:on_ready(function()
            shard_ready = true
        end)

        -- Start next shard after current one is ready
        local timer = uv.timer:new(function()
            if not shard_ready and shard._state.connected then
                self:start()
            end
        end)
        timer:start(1000, 1000)
    end

    return self
end

-- Stop all shards
function ShardManager:stop()
    for _, shard in ipairs(self.shards) do
        shard:close()
    end
    self.shards = {}
    return self
end

-- Get a shard by ID
function ShardManager:get_shard(id)
    return self.shards[id]
end

-- Get all shards
function ShardManager:shards()
    return self.shards
end

-- Dispatch event to all shards
function ShardManager:dispatch(event)
    for _, shard in ipairs(self.shards) do
        shard:emit(event)
    end
    return self
end

-- On ready event
function ShardManager:on_ready(callback)
    if not self.listeners.ready then
        self.listeners.ready = {}
    end
    table.insert(self.listeners.ready, callback)
    return self
end

-- On shard ready
function ShardManager:on_shard_ready(shard_id, callback)
    if not self.listeners["shard_ready"] then
        self.listeners["shard_ready"] = {}
    end
    table.insert(self.listeners["shard_ready"], callback)
    return self
end

-- On shard error
function ShardManager:on_shard_error(shard_id, callback)
    if not self.listeners["shard_error"] then
        self.listeners["shard_error"] = {}
    end
    table.insert(self.listeners["shard_error"], callback)
    return self
end

-- On shard disconnect
function ShardManager:on_shard_disconnect(shard_id, callback)
    if not self.listeners["shard_disconnect"] then
        self.listeners["shard_disconnect"] = {}
    end
    table.insert(self.listeners["shard_disconnect"], callback)
    return self
end

-- Helper to wait for shard to be ready
function ShardManager:wait_for_shard(shard_id, timeout)
    timeout = timeout or 10000
    local start_time = uv.now()

    local wait_fn = function()
        if start_time + timeout < uv.now() then
            return false
        end
        local shard = self.shards[shard_id]
        if shard and shard._state.connected then
            return true
        end
        local timer = uv.timer:new(function()
            self:wait_for_shard(shard_id, timeout)
        end)
        timer:start(100, 100)
        return false
    end

    return wait_fn()
end

return ShardManager
