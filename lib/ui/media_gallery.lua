-- lib/ui/media_gallery.lua
-- MediaGallery component (Components V2), contract mirrors pycord
-- discord.ui.MediaGallery.
--
-- Public Contract:
--   MediaGallery.new(items) -> media_gallery
--     items: array of tables, each { url = string, description = string or nil,
--     spoiler = boolean or nil }. 1 to 10 items.
--
--   media_gallery:add_item(item) -> self
--     Appends one more media item table, same shape as above. Errors if
--     the gallery already has 10 items.
--
--   media_gallery:to_component() -> table
--     Serializes to the Discord MediaGallery component payload (type 12).

local class = require("core.class")
local Item = require("ui.item")

local MAX_ITEMS = 10

local MediaGallery = class("MediaGallery", Item)

local function validate_item(item)
    if type(item) ~= "table" or item.url == nil then
        error("each MediaGallery item requires a url")
    end
    if item.description ~= nil and #tostring(item.description) > 1024 then
        error("MediaGallery item description must be 1024 characters or fewer")
    end
end

function MediaGallery.new(items)
    items = items or {}
    local self = setmetatable(Item.new("media_gallery"), MediaGallery)

    if #items > MAX_ITEMS then
        error("MediaGallery accepts at most " .. MAX_ITEMS .. " items")
    end
    for _, item in ipairs(items) do
        validate_item(item)
    end

    self.items = items
    return self
end

function MediaGallery:add_item(item)
    validate_item(item)
    if #self.items >= MAX_ITEMS then
        error("MediaGallery accepts at most " .. MAX_ITEMS .. " items")
    end
    table.insert(self.items, item)
    return self
end

function MediaGallery:to_component()
    local gallery_items = {}
    for i, item in ipairs(self.items) do
        gallery_items[i] = {
            media = { url = item.url },
            description = item.description,
            spoiler = item.spoiler or false,
        }
    end

    return {
        type = 12,
        items = gallery_items,
    }
end

return MediaGallery
