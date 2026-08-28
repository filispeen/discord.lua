local class = require("../core/class")

local Nameplate = class("Nameplate")
function Nameplate.new(data)
    data = data or {}
    local self = { sku_id = data.sku_id, palette = data.palette, label = data.label, asset = data.asset }
    setmetatable(self, { __index = Nameplate })
    return self
end

function Nameplate:equals(other)
    return other and self.sku_id == other.sku_id and self.palette == other.palette
end

local Collectibles = class("Collectibles")
function Collectibles.new(data)
    data = data or {}
    local self = { nameplate = data.nameplate and Nameplate.new(data.nameplate) or nil }
    setmetatable(self, { __index = Collectibles })
    return self
end

function Collectibles:equals(other)
    if not other then return false end
    if self.nameplate == nil or other.nameplate == nil then return self.nameplate == other.nameplate end
    return self.nameplate:equals(other.nameplate)
end

return { Collectibles = Collectibles, Nameplate = Nameplate }
