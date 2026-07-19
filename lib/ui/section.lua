-- lib/ui/section.lua
-- Section component (Components V2), contract mirrors pycord
-- discord.ui.Section.
--
-- Public Contract:
--   Section.new(opts) -> section
--     opts.components: array of TextDisplay items, 1 to 3
--     opts.accessory: a Thumbnail or Button item, required
--
--   section:to_component() -> table
--     Serializes to the Discord Section component payload (type 9).

local class = require("core.class")
local Item = require("ui.item")

local MAX_TEXT_DISPLAYS = 3

local Section = class("Section", Item)

function Section.new(opts)
    opts = opts or {}
    local self = setmetatable(Item.new("section"), Section)

    local components = opts.components or {}
    if #components == 0 then
        error("Section requires at least 1 component")
    end
    if #components > MAX_TEXT_DISPLAYS then
        error("Section accepts at most " .. MAX_TEXT_DISPLAYS .. " components")
    end
    if opts.accessory == nil then
        error("Section requires an accessory (Thumbnail or Button)")
    end

    self.components = components
    self.accessory = opts.accessory

    return self
end

function Section:to_component()
    local rendered = {}
    for i, component in ipairs(self.components) do
        rendered[i] = component:to_component()
    end

    return {
        type = 9,
        components = rendered,
        accessory = self.accessory:to_component(),
    }
end

return Section
