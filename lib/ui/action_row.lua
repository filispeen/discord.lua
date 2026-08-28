local class = require("../core/class")
local Item = require("./item")

local ActionRow = class("ActionRow", Item)

function ActionRow.new(opts)
    opts = opts or {}
    local self = setmetatable(Item.new("action_row"), ActionRow)
    self.id = opts.id
    self.items = {}
    for _, item in ipairs(opts.items or {}) do self:add_item(item) end
    return self
end

function ActionRow:width()
    local width = 0
    for _, item in ipairs(self.items) do width = width + (item.width or 1) end
    return width
end

function ActionRow:add_item(item)
    if type(item) ~= "table" or type(item.to_component) ~= "function" then error("ActionRow item must be a UI component", 0) end
    if item.type ~= "button" and item.type ~= "select" then error("ActionRow supports Button and Select items only", 0) end
    if self:width() + (item.width or 1) > 5 then error("ActionRow cannot exceed width 5", 0) end
    item.row = nil
    item.parent = self
    self.items[#self.items + 1] = item
    return self
end

function ActionRow:remove(item_or_id)
    for index, item in ipairs(self.items) do
        if item == item_or_id or item.custom_id == item_or_id or item.id == item_or_id then
            item.parent = nil
            table.remove(self.items, index)
            break
        end
    end
    return self
end

function ActionRow:get_item(id)
    for _, item in ipairs(self.items) do
        if item.custom_id == id or item.id == id then return item end
    end
    return nil
end

function ActionRow:to_component()
    local components = {}
    for index, item in ipairs(self.items) do components[index] = item:to_component() end
    local result = { type = 1, components = components }
    if self.id ~= nil then result.id = self.id end
    return result
end

return ActionRow
