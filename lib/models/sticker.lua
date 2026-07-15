-- lib/models/sticker.lua
-- Sticker model for Discord API
--
-- Public Contract:
--   Sticker.new(data) -> Sticker
--     Creates a new Sticker from API data.
--
--   Sticker:id -> string
--     Sticker's unique ID.
--
--   Sticker:name -> string
--     Sticker name.
--
--   Sticker:sort_value -> number
--     Sticker's sort value.
--
--   Sticker:description -> string or nil
--     Sticker description.
--
--   Sticker:pack_id -> string or nil
--     Sticker pack ID.
--
--   Sticker:type -> number
--     Sticker type (1 = standard, 2 = premium).
--
--   Sticker:user -> User or nil
--     Sticker pack owner (for premium stickers).

local class = require("core.class")

-- Sticker class
local Sticker = class("Sticker")

function Sticker.new(data)
    local self = {}
    setmetatable(self, {
        __index = Sticker
    })

    self.id = data.id
    self.name = data.name
    self.sort_value = data.sort_value or 0
    self.description = data.description or nil
    self.pack_id = data.pack_id or nil
    self.type = data.type or 1
    self.user = data.user or nil

    -- Pack info
    if data.pack then
        self.pack = data.pack
        self.pack.id = data.pack.id
        self.pack.name = data.pack.name or nil
        self.pack.sticker_count = data.pack.sticker_count or 0
    end

    return self
end

-- Get sticker URL
function Sticker:get_url()
    return "https://cdn.discordapp.com/stickers/" .. self.id .. ".png"
end

-- Get pack URL
function Sticker:get_pack_url()
    if self.pack_id then
        return "https://cdn.discordapp.com/sticker-packs/" .. self.pack_id .. ".png"
    end
    return nil
end

-- Check if this is a premium sticker
function Sticker:is_premium()
    return self.type == 2
end

return Sticker
