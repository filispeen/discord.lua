-- lib/voice/errors.lua
-- Voice-specific error classes
--
-- Public Contract:
--   Errors are thrown by voice operations when failures occur
--     VoiceClientError - Base voice error
--     VoiceConnectError - Connection failures
--     VoiceDisconnectError - Disconnection failures
--     VoiceAudioError - Audio processing errors

local class = require("core.class")
local errors = require("core.errors")

-- Base voice error (extends HTTPException)
local VoiceClientError = class("VoiceClientError", errors.HTTPException)

VoiceClientError.new = function(message)
    local self = {
        message = message,
    }
    setmetatable(self, VoiceClientError)
    return self
end

VoiceClientError.__tostring = function(self)
    return "VoiceClientError: " .. self.message
end

-- Connection failure error
local VoiceConnectError = class("VoiceConnectError", VoiceClientError)

VoiceConnectError.new = function(message, cause)
    local self = {
        message = message,
        cause = cause,
    }
    setmetatable(self, VoiceConnectError)
    return self
end

VoiceConnectError.__tostring = function(self)
    return "VoiceConnectError: " .. self.message
end

-- Disconnection failure error
local VoiceDisconnectError = class("VoiceDisconnectError", VoiceConnectError)

VoiceDisconnectError.new = function(message, code, reason)
    local self = {
        message = message,
        code = code,
        reason = reason,
    }
    setmetatable(self, VoiceDisconnectError)
    return self
end

VoiceDisconnectError.__tostring = function(self)
    return "VoiceDisconnectError: " .. self.message .. " (code: " .. tostring(self.code) .. ")"
end

-- Audio processing error
local VoiceAudioError = class("VoiceAudioError", VoiceClientError)

VoiceAudioError.new = function(message)
    local self = {
        message = message,
    }
    setmetatable(self, VoiceAudioError)
    return self
end

VoiceAudioError.__tostring = function(self)
    return "VoiceAudioError: " .. self.message
end

local M = {
    VoiceClientError = VoiceClientError,
    VoiceConnectError = VoiceConnectError,
    VoiceDisconnectError = VoiceDisconnectError,
    VoiceAudioError = VoiceAudioError,
}

return M
