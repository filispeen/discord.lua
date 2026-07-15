-- lib/commands/converters.lua
-- Type converters for ext.commands
--
-- Public Contract:
--   converter:convert(ctx, value) -> T
--     Converts a string value to type T.
--     Throws ConverterError on failure.
--
--   converters.string -> string
--     Default string converter (no conversion).
--
--   converters.integer -> integer
--     Converts string to integer.
--
--   converters.boolean -> boolean
--     Converts "true"/"false" to boolean.
--
--   converters.user -> User
--     Converts @user or user ID to User object.
--
--   converters.member -> Member
--     Converts @member or member ID to Member object.
--
--   converters.role -> Role
--     Converts @role or role ID to Role object.
--
--   converters.channel -> Channel
--     Converts #channel or channel ID to Channel object.
--
--   converters.text_channel -> Channel
--     Converts to TextChannel specifically.

local class = require("core.class")

-- Converter error class
local ConverterError = class("ConverterError")
function ConverterError.new(message)
    local self = {}
    setmetatable(self, { __index = ConverterError })
    self.message = message
    return self
end
ConverterError.create = ConverterError.new

-- String converter (no conversion)
local StringConverter = class("StringConverter")
function StringConverter.convert(_, value)
    return value
end

-- Integer converter
local IntegerConverter = class("IntegerConverter")
function IntegerConverter.convert(_, value)
    local num = tonumber(value)
    if not num then
        error(ConverterError.new("Could not convert to integer: " .. tostring(value)), 0)
    end
    return num
end

-- Boolean converter
local BooleanConverter = class("BooleanConverter")
function BooleanConverter.convert(_, value)
    local lower = string.lower(value or "")
    if lower == "true" then
        return true
    elseif lower == "false" then
        return false
    else
        error(ConverterError.new("Could not convert to boolean: " .. tostring(value)), 0)
    end
end

-- User converter
local UserConverter = class("UserConverter")
function UserConverter.convert(ctx, value)
    local type = type(value)
    if type == "string" then
        -- Check if it's a user mention
        if value:sub(1, 1) == "@" and value:sub(2, 2) == "@" then
            local user_id = value:sub(4)
            local user = ctx:get_user(user_id)
            if user then
                return user
            end
            error(ConverterError.new("Could not find user: " .. value), 0)
        else
            -- Treat as user ID
            local user = ctx:get_user(value)
            if not user then
                error(ConverterError.new("Could not find user: " .. value), 0)
            end
            return user
        end
    elseif type == "table" and value.id then
        return value
    else
        error(ConverterError.new("Invalid user: " .. tostring(value)), 0)
    end
end

-- Member converter
local MemberConverter = class("MemberConverter")
function MemberConverter.convert(ctx, value)
    local type = type(value)
    if type == "string" then
        if value:sub(1, 1) == "@" and value:sub(2, 2) == "@" then
            local member_id = value:sub(4)
            local member = ctx:get_member(member_id)
            if member then
                return member
            end
            error(ConverterError.new("Could not find member: " .. value), 0)
        else
            local member = ctx:get_member(value)
            if not member then
                error(ConverterError.new("Could not find member: " .. value), 0)
            end
            return member
        end
    elseif type == "table" and value.id then
        return value
    else
        error(ConverterError.new("Invalid member: " .. tostring(value)), 0)
    end
end

-- Role converter
local RoleConverter = class("RoleConverter")
function RoleConverter.convert(ctx, value)
    local type = type(value)
    if type == "string" then
        if value:sub(1, 1) == "@" and value:sub(2, 2) == "@" then
            local role_id = value:sub(4)
            local role = ctx:get_role(role_id)
            if role then
                return role
            end
            error(ConverterError.new("Could not find role: " .. value), 0)
        else
            local role = ctx:get_role(value)
            if not role then
                error(ConverterError.new("Could not find role: " .. value), 0)
            end
            return role
        end
    elseif type == "table" and value.id then
        return value
    else
        error(ConverterError.new("Invalid role: " .. tostring(value)), 0)
    end
end

-- Channel converter
local ChannelConverter = class("ChannelConverter")
function ChannelConverter.convert(ctx, value)
    local type = type(value)
    if type == "string" then
        if value:sub(1, 1) == "#" then
            local channel_id = value:sub(2)
            local channel = ctx:get_channel(channel_id)
            if channel then
                return channel
            end
            error(ConverterError.new("Could not find channel: " .. value), 0)
        else
            local channel = ctx:get_channel(value)
            if not channel then
                error(ConverterError.new("Could not find channel: " .. value), 0)
            end
            return channel
        end
    elseif type == "table" and value.id then
        return value
    else
        error(ConverterError.new("Invalid channel: " .. tostring(value)), 0)
    end
end

return {
    ConverterError = ConverterError,
    StringConverter = StringConverter,
    IntegerConverter = IntegerConverter,
    BooleanConverter = BooleanConverter,
    UserConverter = UserConverter,
    MemberConverter = MemberConverter,
    RoleConverter = RoleConverter,
    ChannelConverter = ChannelConverter,
    converter = function(ctx, value, type)
        local converters = {
            ["string"] = StringConverter,
            ["integer"] = IntegerConverter,
            ["boolean"] = BooleanConverter,
            ["user"] = UserConverter,
            ["member"] = MemberConverter,
            ["role"] = RoleConverter,
            ["channel"] = ChannelConverter,
            ["text_channel"] = ChannelConverter,
        }

        local converter_class = converters[type]
        if not converter_class then
            error("Unknown converter type: " .. type, 0)
        end

        local converter = converter_class.new()
        return converter:convert(ctx, value)
    end,
}
