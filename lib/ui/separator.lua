-- lib/ui/separator.lua
-- Separator component (Components V2), contract mirrors pycord
-- discord.ui.Separator.
--
-- Public Contract:
--   Separator.new(opts) -> separator
--     opts.divider: boolean or nil - whether to show a visible divider line, defaults to true
--     opts.spacing: string or nil - "small" or "large", defaults to "small"
--
--   separator:to_component() -> table
--     Serializes to the Discord Separator component payload (type 14).

local class = require("core.class")
local Item = require("ui.item")

local SPACING_VALUES = {
    small = 1,
    large = 2,
}

local Separator = class("Separator", Item)

function Separator.new(opts)
    opts = opts or {}
    local self = setmetatable(Item.new("separator"), Separator)

    local spacing = opts.spacing or "small"
    if not SPACING_VALUES[spacing] then
        error("invalid separator spacing: " .. tostring(spacing))
    end

    self.divider = opts.divider
    if self.divider == nil then
        self.divider = true
    end
    self.spacing = spacing

    return self
end

function Separator:to_component()
    return {
        type = 14,
        divider = self.divider,
        spacing = SPACING_VALUES[self.spacing],
    }
end

return Separator
