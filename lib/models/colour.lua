local class = require("../core/class")

local Colour = class("Colour")

function Colour.new(value)
    if type(value) ~= "number" or value % 1 ~= 0 or value < 0 or value > 0xFFFFFF then
        error("Colour value must be an integer from 0 through 0xFFFFFF", 0)
    end
    local self = { value = value }
    setmetatable(self, { __index = Colour })
    return self
end

function Colour.from_rgb(r, g, b)
    for _, value in ipairs({ r, g, b }) do
        if type(value) ~= "number" or value % 1 ~= 0 or value < 0 or value > 255 then
            error("Colour RGB components must be integers from 0 through 255", 0)
        end
    end
    return Colour.new(r * 65536 + g * 256 + b)
end

function Colour.from_hex(value)
    value = tostring(value):gsub("^#", "")
    if not value:match("^[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$") then
        error("Colour hex value must have six hexadecimal digits", 0)
    end
    return Colour.new(tonumber(value, 16))
end

function Colour.default() return Colour.new(0) end
function Colour.teal() return Colour.new(0x1ABC9C) end
function Colour.green() return Colour.new(0x2ECC71) end
function Colour.blue() return Colour.new(0x3498DB) end
function Colour.purple() return Colour.new(0x9B59B6) end
function Colour.magenta() return Colour.new(0xE91E63) end
function Colour.gold() return Colour.new(0xF1C40F) end
function Colour.orange() return Colour.new(0xE67E22) end
function Colour.red() return Colour.new(0xE74C3C) end
function Colour.blurple() return Colour.new(0x5865F2) end
function Colour.dark_theme() return Colour.new(0x313338) end

function Colour:r() return math.floor(self.value / 65536) % 256 end
function Colour:g() return math.floor(self.value / 256) % 256 end
function Colour:b() return self.value % 256 end
function Colour:to_rgb() return self:r(), self:g(), self:b() end
function Colour:to_hex() return string.format("#%06x", self.value) end
function Colour:equals(other) return other and self.value == other.value end

return { Colour = Colour, Color = Colour }
