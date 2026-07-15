-- lib/models/client.lua
-- Main client model for Discord.lua
--
-- Public Contract:
--   Client.new(token, ratelimiter) -> Client
--     Creates a new Discord client.
--
--   Client:http -> table
--     HTTP client instance.
--
--   Client:ratelimiter -> table
--     Rate limiter instance.
--
--   Client:on(event, callback) -> self
--     Subscribe to an event.
--
--   Client:once(event, callback) -> self
--     Subscribe to an event once.
--
--   Client:emit(event, ...) -> self
--     Emit an event.
--
--   Client:off(event, callback) -> self
--     Unsubscribe from an event.
--
--   Client:get_user(id) -> User
--     Get a user by ID.
--
--   Client:get_member(id) -> Member
--     Get a member by ID.
--
--   Client:get_channel(id) -> Channel
--     Get a channel by ID.
--
--   Client:get_role(id) -> Role
--     Get a role by ID.
--
--   Client:get_guild(id) -> Guild
--     Get a guild by ID.

local class = require("core.class")

-- Client class
local Client = class("Client")

function Client.new(token, ratelimiter)
    local self = {
        token = token,
        ratelimiter = ratelimiter or {},
        events = {},
        http = nil,
        gateway = nil,
    }
    setmetatable(self, {
        __index = Client
    })
    return self
end

-- Create HTTP client
function Client:_create_http()
    local ratelimiter = require("http.ratelimiter")
    local client = require("http.client")

    local manager = ratelimiter.Manager.new()
    self.ratelimiter = manager

    local http_client = client.new(self.token, manager)
    self.http = http_client

    return http_client
end

-- Create and start gateway
function Client:start_gateway()
    local gateway_manager = require("gateway.manager")

    self.gateway = gateway_manager.new(self, 1)

    -- Listen for gateway events
    self.gateway:on_shard_ready(function(shard_id, shard)
        self:emit("shard_ready", { shard_id = shard_id, shard = shard })
    end)

    self.gateway:on_shard_error(function(shard_id, shard, error)
        self:emit("shard_error", { shard_id = shard_id, shard = shard, error = error })
    end)

    self.gateway:on_shard_disconnect(function(shard_id, shard, event)
        self:emit("shard_disconnect", { shard_id = shard_id, shard = shard, event = event })
    end)

    self.gateway:on_ready(function()
        self:emit("ready")
    end)

    self.gateway:start()

    return self
end

-- Stop gateway
function Client:stop_gateway()
    if self.gateway then
        self.gateway:stop()
        self.gateway = nil
    end
    return self
end

-- Event methods
function Client:on(event, callback)
    if not self.events[event] then
        self.events[event] = {}
    end
    table.insert(self.events[event], callback)
    return self
end

function Client:once(event, callback)
    local once_fn = function(...)
        callback(...)
        -- luacheck: ignore unused once_fn
        self:off(event, once_fn)
    end
    self:on(event, once_fn)
    return self
end

function Client:emit(event, ...)
    if self.events[event] then
        for _, callback in ipairs(self.events[event]) do
            callback(...)
        end
    end
    return self
end

function Client:off(event, callback)
    if self.events[event] then
        for i, cb in ipairs(self.events[event]) do
            if cb == callback then
                table.remove(self.events[event], i)
                return
            end
        end
    end
    return self
end

-- Gateway-specific event listeners
function Client:on_gateway_ready(callback)
    if not self.listeners.gateway_ready then
        self.listeners.gateway_ready = {}
    end
    table.insert(self.listeners.gateway_ready, callback)
    return self
end

function Client:on_gateway_shard_ready(shard_id, callback)
    if not self.listeners["gateway_shard_ready"] then
        self.listeners["gateway_shard_ready"] = {}
    end
    table.insert(self.listeners["gateway_shard_ready"], callback)
    return self
end

function Client:on_gateway_shard_error(shard_id, callback)
    if not self.listeners["gateway_shard_error"] then
        self.listeners["gateway_shard_error"] = {}
    end
    table.insert(self.listeners["gateway_shard_error"], callback)
    return self
end

function Client:on_gateway_shard_disconnect(shard_id, callback)
    if not self.listeners["gateway_shard_disconnect"] then
        self.listeners["gateway_shard_disconnect"] = {}
    end
    table.insert(self.listeners["gateway_shard_disconnect"], callback)
    return self
end

function Client:on_gateway_event(callback)
    if not self.listeners.gateway_event then
        self.listeners.gateway_event = {}
    end
    table.insert(self.listeners.gateway_event, callback)
    return self
end

-- Getters (these need to be implemented with actual API calls)
function Client:get_user(id)
    if self.http then
        local response = self.http:get("/users/" .. id)
        return response
    end
    return nil
end

function Client:get_member(id)
    -- Guild context needed
    return nil
end

function Client:get_channel(id)
    if self.http then
        local response = self.http:get("/channels/" .. id)
        return response
    end
    return nil
end

function Client:get_role(id)
    -- Guild context needed
    return nil
end

function Client:get_guild(id)
    if self.http then
        local response = self.http:get("/guilds/" .. id)
        return response
    end
    return nil
end

-- Gateway event dispatch methods
function Client:dispatch_gateway_event(event)
    -- Dispatch to gateway event listeners
    if self.listeners.gateway_event then
        for _, cb in ipairs(self.listeners.gateway_event) do
            cb(event)
        end
    end
    return self
end

function Client:dispatch_shard_ready(shard_id, shard)
    -- Dispatch to shard ready listeners
    if self.listeners["gateway_shard_ready"] then
        for _, cb in ipairs(self.listeners["gateway_shard_ready"]) do
            cb(shard_id, shard)
        end
    end
    return self
end

function Client:dispatch_shard_error(shard_id, shard, error)
    -- Dispatch to shard error listeners
    if self.listeners["gateway_shard_error"] then
        for _, cb in ipairs(self.listeners["gateway_shard_error"]) do
            cb(shard_id, shard, error)
        end
    end
    return self
end

function Client:dispatch_shard_disconnect(shard_id, shard, event)
    -- Dispatch to shard disconnect listeners
    if self.listeners["gateway_shard_disconnect"] then
        for _, cb in ipairs(self.listeners["gateway_shard_disconnect"]) do
            cb(shard_id, shard, event)
        end
    end
    return self
end

return Client
