-- lib/core/errors.lua
-- Error classes for discord.lua
--
-- Public Contract:
--   DiscordException(message) -> exception
--     Base exception class for all Discord-related errors
--     message: string - error message
--
--   HTTPException(message, status_code, data) -> exception
--     Error raised for HTTP errors
--     message: string - error message
--     status_code: number - HTTP status code
--     data: table or nil - response data if available
--
--   RateLimited(message, retry_after) -> exception
--     Error raised when rate limited
--     message: string - error message
--     retry_after: number - seconds to wait before retrying
--
--   GatewayError(message, code) -> exception
--     Error raised for gateway WebSocket errors
--     message: string - error message
--     code: number or string - error code from Discord
--
--   NotFound(message, id) -> exception
--     Error raised when a resource is not found
--     message: string - error message
--     id: string or nil - the missing resource ID
--
--   Forbidden(message) -> exception
--     Error raised for permission denied errors
--     message: string - error message

local class = require("core.class")
local DiscordException = class("DiscordException")

-- Base DiscordException
local function DiscordException_new(self, message)
    self.message = message
    return self
end

DiscordException.new = DiscordException_new

function DiscordException:__tostring()
    return self.message
end

-- HTTPException: errors from HTTP requests
local HTTPException = class("HTTPException", DiscordException)

local function HTTPException_new(self, message, status_code, data)
    self.message = message
    self.status_code = status_code
    self.data = data or nil
    return self
end

HTTPException.new = HTTPException_new

function HTTPException:__tostring()
    return "HTTPException: " .. self.message .. " (status: " .. self.status_code .. ")"
end

-- RateLimited: rate limit errors
local RateLimited = class("RateLimited", DiscordException)

local function RateLimited_new(self, message, retry_after)
    self.message = message
    self.retry_after = retry_after or 0
    return self
end

RateLimited.new = RateLimited_new

function RateLimited:__tostring()
    return "RateLimited: " .. self.message .. " (retry_after: " .. self.retry_after .. "s)"
end

-- GatewayError: WebSocket gateway errors
local GatewayError = class("GatewayError", DiscordException)

local function GatewayError_new(self, message, code)
    self.message = message
    self.code = code
    return self
end

GatewayError.new = GatewayError_new

function GatewayError:__tostring()
    return "GatewayError: " .. self.message .. " (code: " .. tostring(self.code) .. ")"
end

-- NotFound: resource not found
local NotFound = class("NotFound", DiscordException)

local function NotFound_new(self, message, id)
    self.message = message
    self.id = id
    return self
end

NotFound.new = NotFound_new

function NotFound:__tostring()
    return "NotFound: " .. self.message .. " (id: " .. tostring(self.id) .. ")"
end

-- Forbidden: permission denied
local Forbidden = class("Forbidden", DiscordException)

local function Forbidden_new(self, message)
    self.message = message
    return self
end

Forbidden.new = Forbidden_new

function Forbidden:__tostring()
    return "Forbidden: " .. self.message
end

-- TimeoutError: raised by Bot:wait_for when no matching event arrives
-- before the timeout elapses, mirrors pycord's asyncio.TimeoutError.
local TimeoutError = class("TimeoutError", DiscordException)

function TimeoutError.new(message)
    local self = setmetatable({}, TimeoutError)
    self.message = message or "Timed out waiting for event"
    return self
end

function TimeoutError:__tostring()
    return "TimeoutError: " .. self.message
end

-- Factory functions for convenience
function DiscordException.create(message)
    return DiscordException.new(message)
end

function HTTPException.create(message, status_code, data)
    return HTTPException.new(message, status_code, data)
end

function RateLimited.create(message, retry_after)
    return RateLimited.new(message, retry_after)
end

function GatewayError.create(message, code)
    return GatewayError.new(message, code)
end

function NotFound.create(message, id)
    return NotFound.new(message, id)
end

function Forbidden.create(message)
    return Forbidden.new(message)
end

function TimeoutError.create(message)
    return TimeoutError.new(message)
end

return {
    DiscordException = DiscordException,
    HTTPException = HTTPException,
    RateLimited = RateLimited,
    GatewayError = GatewayError,
    NotFound = NotFound,
    Forbidden = Forbidden,
    TimeoutError = TimeoutError,
}
