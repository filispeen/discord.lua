local class = require("../core/class")

local Asset = class("Asset")

local function is_power_of_two(value)
    if type(value) ~= "number" or value < 16 or value > 4096 or value % 1 ~= 0 then return false end
    while value > 1 do
        if value % 2 ~= 0 then return false end
        value = value / 2
    end
    return true
end

function Asset.new(url, key, animated)
    if type(url) ~= "string" or url == "" then error("Asset.new requires a non-empty URL", 0) end
    local self = { url = url, key = key or "", animated = animated or false }
    setmetatable(self, { __index = Asset })
    return self
end

function Asset.from_avatar(user_id, avatar)
    if not avatar then return nil end
    local animated = avatar:sub(1, 2) == "a_"
    return Asset.new("https://cdn.discordapp.com/avatars/" .. user_id .. "/" .. avatar .. (animated and ".gif" or ".png"), avatar, animated)
end

function Asset.from_guild_icon(guild_id, icon)
    if not icon then return nil end
    local animated = icon:sub(1, 2) == "a_"
    return Asset.new("https://cdn.discordapp.com/icons/" .. guild_id .. "/" .. icon .. (animated and ".gif" or ".png"), icon, animated)
end

function Asset.from_icon(object_id, icon, path)
    if not icon then return nil end
    local animated = icon:sub(1, 2) == "a_"
    return Asset.new("https://cdn.discordapp.com/" .. path .. "/" .. object_id .. "/" .. icon .. (animated and ".gif" or ".png"), icon, animated)
end

function Asset.from_collectible(asset, animated)
    if not asset then return nil end
    return Asset.new("https://cdn.discordapp.com/assets/collectibles/" .. asset .. (animated and ".gif" or ".png"), asset, animated)
end

function Asset:is_animated()
    return self.animated
end

function Asset:replace(opts)
    opts = opts or {}
    local format = opts.format
    local size = opts.size
    if format and format ~= "png" and format ~= "jpg" and format ~= "jpeg" and format ~= "webp" and format ~= "gif" then
        error("Asset format must be png, jpg, jpeg, webp or gif", 0)
    end
    if format == "gif" and not self.animated then error("static Asset cannot use gif format", 0) end
    if size and not is_power_of_two(size) then error("Asset size must be a power of two from 16 through 4096", 0) end
    local url, query = self.url:match("^([^?]+)%??(.*)$")
    if format then url = url:gsub("%.[^%.]+$", "." .. format) end
    if size then query = "size=" .. size end
    if query ~= "" then url = url .. "?" .. query end
    return Asset.new(url, self.key, format == "gif" or (not format and self.animated))
end

function Asset:with_size(size)
    return self:replace({ size = size })
end

function Asset:with_format(format)
    return self:replace({ format = format })
end

function Asset:equals(other)
    return other and self.url == other.url
end

return Asset
