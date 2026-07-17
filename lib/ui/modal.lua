-- lib/ui/modal.lua
-- Modal class for text-input popups, resolved via interaction:respond({type = "modal"}).
-- Contract mirrors pycord discord.ui.Modal (BaseModal).
--
-- Public Contract:
--   Modal.new(opts) -> modal
--     opts.title: string - up to 45 characters
--     opts.custom_id: string or nil - up to 100 characters, auto generated if omitted
--
--   modal:add_item(item) -> self
--     Attaches a text input item. Errors if more than 5 items.
--
--   modal:to_component() -> table
--     Serializes the modal to the Discord interaction response payload.
--
--   modal.on_submit: function or nil
--     Optional callback invoked with the interaction when the modal is submitted.

local class = require("core.class")

local MAX_ITEMS = 5

local Modal = class("Modal")

function Modal.new(opts)
    opts = opts or {}

    if opts.title == nil then
        error("title is required")
    end

    if #tostring(opts.title) > 45 then
        error("title must be 45 characters or fewer")
    end

    if opts.custom_id ~= nil and #tostring(opts.custom_id) > 100 then
        error("custom_id must be 100 characters or fewer")
    end

    local self = setmetatable({}, Modal)
    self.title = opts.title
    self.custom_id = opts.custom_id or ("modal_" .. tostring(math.random(1, 1e9)))
    self.items = {}
    self.on_submit = nil
    self.stopped = false

    return self
end

function Modal:add_item(item)
    if #self.items >= MAX_ITEMS then
        error("modal can only hold 5 items")
    end

    table.insert(self.items, item)
    return self
end

function Modal:to_component()
    local rows = {}
    for _, item in ipairs(self.items) do
        table.insert(rows, {
            type = 1,
            components = { item.to_component and item:to_component() or item },
        })
    end

    return {
        title = self.title,
        custom_id = self.custom_id,
        components = rows,
    }
end

function Modal:stop()
    self.stopped = true
    return self
end

return Modal
