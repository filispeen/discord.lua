-- lib/ui/view.lua
-- View class, holds up to 5 rows of components and an optional timeout.
-- Contract mirrors pycord discord.ui.View (BaseView / View).
--
-- Public Contract:
--   View.new(opts) -> view
--     opts.timeout: number or nil - milliseconds before on_timeout fires. nil means no timeout.
--
--   view:add(item) -> self
--     Attaches a UI item (Button or Select). Assigns an automatic row if item.row is nil.
--     Errors if all 5 rows are full.
--
--   view:remove(item_or_custom_id) -> self
--     Detaches an item by reference or by custom_id.
--
--   view:clear() -> self
--     Removes all items.
--
--   view:timeout(ms) -> self
--     Sets or updates the timeout in milliseconds.
--
--   view:to_components() -> table
--     Serializes all items into Discord action row payloads, grouped by row.
--
--   view:stop() -> self
--     Marks the view as stopped and cancels any pending timeout.
--
--   view.on_timeout: function or nil
--     Optional callback invoked when the timeout elapses.

local class = require("core.class")

local MAX_ROWS = 5

local View = class("View")

function View.new(opts)
    opts = opts or {}
    local self = setmetatable({}, View)
    self.items = {}
    self.timeout_ms = opts.timeout
    self.stopped = false
    self.on_timeout = nil
    self._timer_handle = nil
    return self
end

local function next_free_row(self)
    local counts = {}
    for i = 0, MAX_ROWS - 1 do
        counts[i] = 0
    end

    for _, item in ipairs(self.items) do
        if item.row ~= nil then
            counts[item.row] = counts[item.row] + 1
        end
    end

    for i = 0, MAX_ROWS - 1 do
        if counts[i] < 5 then
            return i
        end
    end

    return nil
end

function View:add(item)
    if item.row == nil then
        local row = next_free_row(self)
        if row == nil then
            error("view already has 5 full rows, cannot add more items")
        end
        item.row = row
    end

    item.view = self
    table.insert(self.items, item)
    return self
end

function View:remove(item_or_custom_id)
    local target_id = item_or_custom_id
    if type(item_or_custom_id) == "table" then
        target_id = item_or_custom_id.custom_id
    end

    for i, item in ipairs(self.items) do
        if item == item_or_custom_id or item.custom_id == target_id then
            table.remove(self.items, i)
            return self
        end
    end

    return self
end

-- Finds an attached item by custom_id, used to route an incoming
-- INTERACTION_CREATE payload to the item that should handle it.
function View:find_item(custom_id)
    for _, item in ipairs(self.items) do
        if item.custom_id == custom_id then
            return item
        end
    end
    return nil
end

function View:clear()
    self.items = {}
    return self
end

function View:timeout(ms)
    self.timeout_ms = ms
    return self
end

function View:to_components()
    local rows = {}
    for i = 0, MAX_ROWS - 1 do
        rows[i] = {}
    end

    for _, item in ipairs(self.items) do
        local row_index = item.row or 0
        table.insert(rows[row_index], item:to_component())
    end

    local components = {}
    for i = 0, MAX_ROWS - 1 do
        if #rows[i] > 0 then
            table.insert(components, {
                type = 1,
                components = rows[i],
            })
        end
    end

    return components
end

function View:stop()
    self.stopped = true
    self._timer_handle = nil
    return self
end

return View
