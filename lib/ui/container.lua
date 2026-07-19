-- lib/ui/container.lua
-- Container component (Components V2), contract mirrors pycord
-- discord.ui.Container.
--
-- Public Contract:
--   Container.new(opts) -> container
--     opts.components: array of items with :to_component() (TextDisplay,
--     Section, MediaGallery, Separator, or a View's action rows), required.
--     opts.accent_color: number or nil - a color int shown as a left border
--     opts.spoiler: boolean or nil - defaults to false
--
--   container:add_item(item) -> self
--     Appends one more child component item.
--
--   container:to_component() -> table
--     Serializes to the Discord Container component payload (type 17).

local class = require("core.class")
local Item = require("ui.item")

local Container = class("Container", Item)

function Container.new(opts)
    opts = opts or {}
    local self = setmetatable(Item.new("container"), Container)

    self.components = opts.components or {}
    self.accent_color = opts.accent_color
    self.spoiler = opts.spoiler or false

    return self
end

function Container:add_item(item)
    table.insert(self.components, item)
    return self
end

function Container:to_component()
    local rendered = {}
    for i, component in ipairs(self.components) do
        rendered[i] = component:to_component()
    end

    local component = {
        type = 17,
        components = rendered,
        spoiler = self.spoiler,
    }

    if self.accent_color ~= nil then
        component.accent_color = self.accent_color
    end

    return component
end

return Container
