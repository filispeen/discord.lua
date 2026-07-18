-- lib/ui/button.lua
-- Button component for discord.lua UI, contract mirrors pycord discord.ui.Button
--
-- Public Contract:
--   Button.new(opts) -> button
--     opts.style: string - one of "primary", "secondary", "success", "danger", "link". Defaults to "secondary".
--     opts.label: string or nil - up to 80 characters
--     opts.custom_id: string or nil - up to 100 characters, required unless style is "link"
--     opts.url: string or nil - required when style is "link", mutually exclusive with custom_id
--     opts.emoji: string or nil
--     opts.disabled: boolean - defaults to false
--     opts.row: number or nil - 0..4
--
--   button:to_component() -> table
--     Serializes to the Discord button component payload (type 2).

local class = require("core.class")
local Item = require("ui.item")

local VALID_STYLES = {
    primary = true,
    secondary = true,
    success = true,
    danger = true,
    link = true,
}

local Button = class("Button", Item)

function Button.new(opts)
    opts = opts or {}
    local self = setmetatable(Item.new("button"), Button)

    local style = opts.style or "secondary"
    if not VALID_STYLES[style] then
        error("invalid button style: " .. tostring(style))
    end

    if opts.label ~= nil and #tostring(opts.label) > 80 then
        error("label must be 80 characters or fewer")
    end

    if opts.custom_id ~= nil and #tostring(opts.custom_id) > 100 then
        error("custom_id must be 100 characters or fewer")
    end

    if opts.custom_id ~= nil and opts.url ~= nil then
        error("cannot mix both url and custom_id with Button")
    end

    if opts.url ~= nil then
        style = "link"
    end

    if style == "link" and opts.url == nil then
        error("url is required when style is link")
    end

    if style ~= "link" and opts.custom_id == nil then
        error("custom_id is required unless style is link")
    end

    self.style = style
    self.label = opts.label
    self.custom_id = opts.custom_id
    self.url = opts.url
    self.emoji = opts.emoji
    self.disabled = opts.disabled or false
    self.callback = opts.callback
    self:set_row(opts.row)

    return self
end

function Button:to_component()
    local component = {
        type = 2,
        style = self.style,
        disabled = self.disabled,
    }

    if self.label ~= nil then
        component.label = self.label
    end

    if self.emoji ~= nil then
        component.emoji = self.emoji
    end

    if self.style == "link" then
        component.url = self.url
    else
        component.custom_id = self.custom_id
    end

    return component
end

return Button
