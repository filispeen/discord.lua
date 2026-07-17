-- lib/ui/item.lua
-- Base class for UI components attached to a View or Modal
--
-- Public Contract:
--   Item.new(kind) -> item
--     kind: string - component type identifier ("button", "select", etc.)
--
--   item:to_component() -> table
--     Serializes the item to a Discord component payload. Subclasses override this.
--
--   item.row -> number or nil
--     The 0..4 action row the item belongs to, or nil for automatic layout.
--
--   item.view -> View or nil
--     Set by View:add() when the item is attached.

local class = require("core.class")

local Item = class("Item")

function Item.new(kind)
    local self = setmetatable({}, Item)
    self.type = kind
    self.row = nil
    self.view = nil
    self.disabled = false
    return self
end

function Item:set_row(row)
    if row ~= nil and (row < 0 or row > 4) then
        error("row must be between 0 and 4")
    end
    self.row = row
    return self
end

function Item:to_component()
    error("to_component must be implemented by subclass")
end

return Item
