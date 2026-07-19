-- lib/ui/label.lua
-- Label component (Components V2), contract mirrors pycord discord.ui.Label.
-- Wraps a single input component (InputText, Select, or FileUpload) with a
-- label and optional description, used inside modals built with the new
-- Components V2 modal API instead of legacy action rows.
--
-- Public Contract:
--   Label.new(opts) -> label
--     opts.text: string - the label text shown above the input, up to 45 characters
--     opts.description: string or nil - up to 100 characters
--     opts.component: an item with :to_component(), the wrapped input
--
--   label:to_component() -> table
--     Serializes to the Discord Label component payload (type 18).

local class = require("core.class")
local Item = require("ui.item")

local Label = class("Label", Item)

function Label.new(opts)
    opts = opts or {}
    local self = setmetatable(Item.new("label"), Label)

    if opts.text == nil then
        error("text is required for Label")
    end
    if #tostring(opts.text) > 45 then
        error("Label text must be 45 characters or fewer")
    end
    if opts.description ~= nil and #tostring(opts.description) > 100 then
        error("Label description must be 100 characters or fewer")
    end
    if opts.component == nil then
        error("Label requires a wrapped component (InputText, Select, or FileUpload)")
    end

    self.text = opts.text
    self.description = opts.description
    self.component = opts.component

    return self
end

function Label:to_component()
    local component = {
        type = 18,
        label = self.text,
        component = self.component:to_component(),
    }

    if self.description ~= nil then
        component.description = self.description
    end

    return component
end

return Label
