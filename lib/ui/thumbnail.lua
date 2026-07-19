-- lib/ui/thumbnail.lua
-- Thumbnail component (Components V2), contract mirrors pycord
-- discord.ui.Thumbnail. Used as a Section's accessory, or standalone.
--
-- Public Contract:
--   Thumbnail.new(opts) -> thumbnail
--     opts.url: string - media URL (attachment:// or https://)
--     opts.description: string or nil - alt text, up to 1024 characters
--     opts.spoiler: boolean or nil - defaults to false
--
--   thumbnail:to_component() -> table
--     Serializes to the Discord Thumbnail component payload (type 11).

local class = require("core.class")
local Item = require("ui.item")

local Thumbnail = class("Thumbnail", Item)

function Thumbnail.new(opts)
    opts = opts or {}
    local self = setmetatable(Item.new("thumbnail"), Thumbnail)

    if opts.url == nil then
        error("url is required for Thumbnail")
    end
    if opts.description ~= nil and #tostring(opts.description) > 1024 then
        error("description must be 1024 characters or fewer")
    end

    self.url = opts.url
    self.description = opts.description
    self.spoiler = opts.spoiler or false

    return self
end

function Thumbnail:to_component()
    local component = {
        type = 11,
        media = { url = self.url },
        spoiler = self.spoiler,
    }

    if self.description ~= nil then
        component.description = self.description
    end

    return component
end

return Thumbnail
