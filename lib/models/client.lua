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

return Client
