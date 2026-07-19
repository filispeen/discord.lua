-- lib/ui/text_display.lua
-- TextDisplay component (Components V2), contract mirrors pycord
-- discord.ui.TextDisplay.
--
-- Public Contract:
--   TextDisplay.new(content) -> text_display
--     content: string - markdown text, up to 4000 characters
--
--   text_display:to_component() -> table
--     Serializes to the Discord TextDisplay component payload (type 10).

local class = require("core.class")
local Item = require("ui.item")

local TextDisplay = class("TextDisplay", Item)

function TextDisplay.new(content)
    local self = setmetatable(Item.new("text_display"), TextDisplay)

    if content == nil then
        error("content is required for TextDisplay")
    end
    if #tostring(content) > 4000 then
        error("content must be 4000 characters or fewer")
    end

    self.content = content
    return self
end

function TextDisplay:to_component()
    return {
        type = 10,
        content = self.content,
    }
end

return TextDisplay
