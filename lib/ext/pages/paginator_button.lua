-- lib/ext/pages/paginator_button.lua
-- PaginatorButton: a navigation button used by Paginator, contract mirrors
-- pycord discord.ext.pages.PaginatorButton.
--
-- Public Contract:
--   PaginatorButton.new(button_type, opts) -> paginator_button
--     button_type: string - one of "first", "prev", "next", "last", "page_indicator"
--     opts.label: string or nil - defaults to a capitalized button_type
--     opts.emoji: string or nil
--     opts.style: string or nil - defaults to "success" (mirrors pycord's green)
--     opts.disabled: boolean or nil - defaults to false
--     opts.custom_id: string or nil
--     opts.row: number or nil - defaults to 0
--     opts.loop_label: string or nil - label shown instead when Paginator.loop_pages is true

local class = require("core.class")

local VALID_TYPES = {
    first = true,
    prev = true,
    next = true,
    last = true,
    page_indicator = true,
}

local function capitalize(str)
    return str:sub(1, 1):upper() .. str:sub(2)
end

local PaginatorButton = class("PaginatorButton")

function PaginatorButton.new(button_type, opts)
    opts = opts or {}

    if not VALID_TYPES[button_type] then
        error("invalid PaginatorButton type: " .. tostring(button_type), 0)
    end

    local self = setmetatable({}, PaginatorButton)
    self.button_type = button_type

    local label = opts.label
    if label == nil and opts.emoji == nil then
        label = capitalize(button_type)
    end
    self.label = label
    self.emoji = opts.emoji
    self.style = opts.style or "success"
    self.disabled = opts.disabled or false
    self.custom_id = opts.custom_id
    self.row = opts.row or 0
    self.loop_label = opts.loop_label or self.label
    self.paginator = nil

    return self
end

return PaginatorButton
