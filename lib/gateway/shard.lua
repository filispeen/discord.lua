-- lib/gateway/shard.lua
-- Single shard WebSocket connection
--
-- Public Contract:
--   Shard.new(client, shard_id, total_shards) -> Shard
--     Creates a new Shard.
--
--   Shard:connect() -> nil
--     Connects to the gateway.
--
--   Shard:identify(data) -> nil
--     Sends identify packet.
--
--   Shard:resume(session_id, seq) -> nil
--     Resumes a session.
--
--   Shard:send_heartbeat() -> nil
--     Sends a heartbeat.
--
--   Shard:on_ready(callback) -> self
--     Listen for READY event.
--
--   Shard:on_event(event, callback) -> self
--     Listen for gateway events.
--
--   Shard:dispatch(event) -> nil
--     Dispatches an event to listeners.
--
--   Shard:close() -> nil
--     Closes the connection.

local class = require("core.class")
local errors = require("core.errors")
local opcodes = require("gateway.opcodes")
local json = require("dkjson")
local uv = package.loaded["mock_luv"] or require("luv")

-- Shard class
local Shard = class("Shard")

-- Internal state
Shard._state = {
    connected = false,
    heartbeat_interval = nil,
    last_heartbeat = 0,
    last_ack = 0,
    missed_acks = 0,
    session_id = nil,
    seq = 0,
}

-- Create a new Shard
function Shard.new(client, shard_id, total_shards)
    local self = {
        client = client,
        shard_id = shard_id,
        total_shards = total_shards,
        ws = nil,
        listeners = {},
    }
    setmetatable(self, { __index = Shard })
    self:reset_state()
    return self
end

-- Get shard ID
function Shard:shard_id()
    return self.shard_id
end

-- Get total shards
function Shard:total_shards()
    return self.total_shards
end

-- Get shard affinity
function Shard:shard_affinity()
    return self.shard_affinity
end

-- Reset internal state
function Shard:reset_state()
    self._state.connected = false
    self._state.heartbeat_interval = nil
    self._state.last_heartbeat = 0
    self._state.last_ack = 0
    self._state.missed_acks = 0
    self._state.session_id = nil
    self._state.seq = 0
end

-- Connect to the gateway
function Shard:connect()
    if self._state.connected then
        return self
    end

    -- Get gateway URL
    local gateway_url = self.client:get("/gateway/bot")
    if not gateway_url then
        error("Failed to get gateway URL")
    end

    -- Create WebSocket connection
    local ws = require("coro-websocket").connect(gateway_url)

    -- Handle open event
    ws:on("open", function()
        self:send({ op = opcodes.CONNECT, d = {} })
        self._state.connected = true
    end)

    -- Handle message event
    ws:on("message", function(msg)
        local parsed = pcall(function()
            return json.decode(msg)
        end)
        if not parsed then
            return
        end

        self:dispatch(parsed)
    end)

    -- Handle close event
    ws:on("close", function(code, reason)
        self:close()
    end)

    -- Handle error event
    ws:on("error", function(err)
        self:emit("error", errors.GatewayError.create("WebSocket error: " .. tostring(err)))
    end)

    return self
end

-- Send identify packet
function Shard:identify(data)
    self:send({ op = opcodes.IDENTIFY, d = data })
    return self
end

-- Send resume packet
function Shard:resume(session_id, seq)
    self:send({ op = opcodes.RESUME, d = { token = self.client.token, session_id = session_id, seq = seq } })
    return self
end

-- Send heartbeat
function Shard:send_heartbeat()
    local heartbeat = { op = opcodes.HEARTBEAT, d = { seq = self._state.seq } }
    self:send(heartbeat)
    self._state.last_heartbeat = os.time()
    return self
end

-- Send a WebSocket message
function Shard:send(msg)
    if self.ws then
        self.ws:send(json.encode(msg))
    end
    return self
end

-- Close the connection
function Shard:close()
    if self._state.connected then
        if self.ws then
            self.ws:close()
            self.ws = nil
        end
        self._state.connected = false
        self._state.heartbeat_interval = nil
        self._state.missed_acks = 0
        self:emit("disconnect", { code = 1000, reason = "Connection closed" })
    end
    return self
end

-- Dispatch event to listeners
function Shard:dispatch(event)
    if event.op == opcodes.READY then
        self._state.seq = event.d.seq or 0
        self._state.connected = true
        self:emit("ready", event.d)
        self:start_heartbeat()
        return
    end

    if event.op == opcodes.HEARTBEAT_ACK then
        self._state.last_ack = event.d.seq or 0
        self._state.missed_acks = 0
        return
    end

    if event.op == opcodes.DISCONNECTED then
        self:close()
        return
    end

    if event.op == opcodes.RECONNECT then
        self:close()
        return
    end

    -- Dispatch to general event listeners
    self:emit("event", event)
    return self
end

-- Start heartbeat timer
function Shard:start_heartbeat()
    local interval = self.client:get("GET /gateway/bot", function(response)
        return response.data.hub or response.data.heartbeat_interval
    end)

    if not interval then
        return
    end

    interval = tonumber(interval) or 5000
    self._state.heartbeat_interval = interval

    -- Clear existing timer
    self:clear_heartbeat()

    -- Start new timer
    local heartbeat = function()
        self:send_heartbeat()
    end

    local timer = uv.timer:new(function()
        heartbeat()
    end)
    timer:start(interval, interval)
end

-- Clear heartbeat timer
function Shard:clear_heartbeat()
    if self._state.heartbeat_timer then
        self._state.heartbeat_timer:stop()
        self._state.heartbeat_timer = nil
    end
end

-- Emit event to listeners
function Shard:emit(event, ...)
    if self.listeners[event] then
        for _, callback in ipairs(self.listeners[event]) do
            callback(...)
        end
    end
    return self
end

-- On ready event
function Shard:on_ready(callback)
    self._state.on_ready = callback
    return self
end

-- On event
function Shard:on_event(event, callback)
    if not self.listeners[event] then
        self.listeners[event] = {}
    end
    table.insert(self.listeners[event], callback)
    return self
end

-- On disconnect
function Shard:on_disconnect(callback)
    local orig_disconnect = self.listeners.disconnect or {}
    self.listeners.disconnect = function(...)
        for _, cb in ipairs(orig_disconnect) do
            cb(...)
        end
        callback(...)
    end
    return self
end

-- On error
function Shard:on_error(callback)
    if not self.listeners.error then
        self.listeners.error = {}
    end
    table.insert(self.listeners.error, callback)
    return self
end

return Shard
