-- lib/gateway/manager.lua
-- Shard manager for multiple WebSocket connections
--
-- Public Contract:
--   ShardManager.new(client, max_concurrency) -> ShardManager
--     Creates a new ShardManager.
--
--   ShardManager:start() -> nil
--     Starts all shards with max_concurrency limit.
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
--
--   ShardManager:on_shard_ready(shard_id, callback) -> self
--     Listen for individual shard ready event.
--
--   ShardManager:on_shard_error(shard_id, callback) -> self
--     Listen for individual shard error event.
--
--   ShardManager:on_shard_disconnect(shard_id, callback) -> self
--     Listen for individual shard disconnect event.
--
--   ShardManager:wait_for_shard(shard_id, timeout) -> boolean
--     Wait for a shard to be ready (deprecated, use on_shard_ready).

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
        _shards = {},
        listeners = {},
    }
    setmetatable(self, { __index = ShardManager })
    return self
end

-- Start all shards with auto-sharding support
function ShardManager:start()
    -- Get shard configuration from gateway. Discord returns
    -- { url, shards, session_start_limit = { max_concurrency, ... } },
    -- not wrapped in a "data" key.
    local gateway_info = self.client:get("/gateway/bot")
    if not gateway_info then
        return self
    end

    -- Parse shard count and max concurrency
    local shards = gateway_info.shards or 1
    local max_concurrency = 1
    if gateway_info.session_start_limit then
        max_concurrency = gateway_info.session_start_limit.max_concurrency or 1
    end

    -- Update max concurrency
    self.max_concurrency = math.min(self.max_concurrency, max_concurrency)

    -- Create shards
    for i = 1, shards do
        local shard_id = i - 1
        local shard = Shard.new(self.client, shard_id, shards)
        shard:on_event("event", function(payload)
            self:_forward_dispatch(payload)
        end)
        self._shards[shard_id] = shard
    end

    -- Start shards respecting max_concurrency
    local ready_count = 0
    local started_count = 0

    local start_next
    local on_shard_ready

    local function fire_ready_listeners_once_all_up(ready_payload)
        if ready_count >= shards and self.listeners.ready then
            for _, callback in ipairs(self.listeners.ready) do
                callback(ready_payload)
            end
        end
    end

    on_shard_ready = function(shard_id, shard)
        return function(ready_payload)
            ready_count = ready_count + 1

            if self.listeners["shard_ready"] then
                for _, callback in ipairs(self.listeners["shard_ready"]) do
                    callback(shard_id, shard, ready_payload)
                end
            end

            fire_ready_listeners_once_all_up(ready_payload)
            if ready_count < self.max_concurrency then
                start_next()
            end
        end
    end

    start_next = function()
        if ready_count >= self.max_concurrency and started_count < shards then
            for i = started_count, shards - 1 do
                local shard = self._shards[i]
                if shard and not shard._state.connected then
                    shard:connect()
                    shard:on_ready(on_shard_ready(i, shard))
                    started_count = started_count + 1
                    break
                end
            end
        end
    end

    -- Start initial batch respecting max_concurrency
    for i = 0, math.min(shards - 1, self.max_concurrency - 1) do
        local shard = self._shards[i]
        if shard and not shard._state.connected then
            shard:connect()
            shard:on_ready(on_shard_ready(i, shard))
            started_count = started_count + 1
        end
    end

    return self
end

-- Stop all shards
function ShardManager:stop()
    for _, shard in pairs(self._shards) do
        shard:close()
    end
    self._shards = {}
    return self
end

-- Get a shard by ID
function ShardManager:get_shard(id)
    return self._shards[id]
end

-- Computes which shard a guild belongs to, per Discord's sharding formula:
-- shard_id = (guild_id >> 22) % num_shards. guild_id is a snowflake, often
-- passed as a string since it can exceed the safe integer range as text;
-- the shift is done via division since Lua's numbers are doubles and
-- native bitwise ops are not safe/available across all Lua 5.1/LuaJIT
-- setups for numbers this large.
function ShardManager:guild_shard_id(guild_id)
    local num_shards = 0
    for _ in pairs(self._shards) do
        num_shards = num_shards + 1
    end
    if num_shards == 0 then
        return 0
    end

    local id = tonumber(guild_id) or 0
    local shifted = math.floor(id / 4194304) -- id >> 22
    return shifted % num_shards
end

-- Gets the shard responsible for a given guild.
function ShardManager:get_shard_for_guild(guild_id)
    return self:get_shard(self:guild_shard_id(guild_id))
end

-- Get all shards
function ShardManager:shards()
    return self._shards
end

-- Dispatch event to all shards
function ShardManager:dispatch(event)
    for _, shard in pairs(self._shards) do
        shard:emit(event)
    end
    return self
end

-- Sends a voice state update (opcode 4) through the shard responsible
-- for the given guild. channel_id = nil disconnects from voice.
function ShardManager:voice_state_update(guild_id, channel_id, self_mute, self_deaf)
    local shard = self:get_shard_for_guild(guild_id)
    if not shard then
        return false, "no shard available for guild " .. tostring(guild_id)
    end
    shard:voice_state_update(guild_id, channel_id, self_mute, self_deaf)
    return true
end

-- Subscribe to a named gateway dispatch event (e.g. "MESSAGE_CREATE").
-- Fires with the event's d payload, mirroring Shard:emit(event.t, event.d).
function ShardManager:on_dispatch(name, callback)
    if not self.listeners.dispatch then
        self.listeners.dispatch = {}
    end
    if not self.listeners.dispatch[name] then
        self.listeners.dispatch[name] = {}
    end
    table.insert(self.listeners.dispatch[name], callback)
    return self
end

-- Internal: routes a raw gateway payload (op/d/s/t) from any shard to
-- listeners registered via on_dispatch, keyed by payload.t.
function ShardManager:_forward_dispatch(payload)
    if not payload or not payload.t then
        return
    end
    local subs = self.listeners.dispatch and self.listeners.dispatch[payload.t]
    if not subs then
        return
    end
    for _, cb in ipairs(subs) do
        cb(payload.d)
    end
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
function ShardManager:on_shard_ready(_shard_id, callback)
    if not self.listeners["shard_ready"] then
        self.listeners["shard_ready"] = {}
    end
    table.insert(self.listeners["shard_ready"], callback)
    return self
end

-- On shard error
function ShardManager:on_shard_error(_shard_id, callback)
    if not self.listeners["shard_error"] then
        self.listeners["shard_error"] = {}
    end
    table.insert(self.listeners["shard_error"], callback)
    return self
end

-- On shard disconnect
function ShardManager:on_shard_disconnect(_shard_id, callback)
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
        local shard = self._shards[shard_id]
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
