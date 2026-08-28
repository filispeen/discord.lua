local class = require("../core/class")
local Asset = require("./asset")

local PartialEmoji = class("PartialEmoji")

function PartialEmoji.new(data)
    if type(data) == "string" then return PartialEmoji.from_str(data) end
    data = data or {}
    local self = { id = data.id, name = data.name, animated = data.animated or false }
    setmetatable(self, { __index = PartialEmoji })
    return self
end

function PartialEmoji.from_dict(data)
    return PartialEmoji.new(data)
end

function PartialEmoji.from_str(value)
    local animated, name, id = value:match("^<?(a?):?([%w_]+):(%d+)>?$")
    if id then return PartialEmoji.new({ id = id, name = name, animated = animated == "a" }) end
    return PartialEmoji.new({ name = value, animated = false })
end

function PartialEmoji:to_dict()
    local data = { name = self.name }
    if self.id then data.id = self.id end
    if self.animated then data.animated = true end
    return data
end

function PartialEmoji:to_string()
    if not self.id then return self.name or "_" end
    return "<" .. (self.animated and "a" or "") .. ":" .. (self.name or "_") .. ":" .. self.id .. ">"
end

function PartialEmoji:as_reaction()
    return self.id and ((self.name or "") .. ":" .. self.id) or self.name
end

function PartialEmoji:is_custom_emoji() return self.id ~= nil end
function PartialEmoji:is_unicode_emoji() return self.id == nil end

function PartialEmoji:asset()
    if not self.id then return nil end
    return Asset.new("https://cdn.discordapp.com/emojis/" .. self.id .. (self.animated and ".gif" or ".png"), self.id, self.animated)
end

function PartialEmoji:equals(other)
    if not other then return false end
    return self.id and self.id == other.id or (not self.id and not other.id and self.name == other.name)
end

return PartialEmoji
