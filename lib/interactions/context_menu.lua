-- lib/interactions/context_menu.lua
-- Context menu interaction handler
--
-- Public Contract:
--   ContextMenuCommand.new(target_type, name, description) -> ContextMenuCommand
--
--   ContextMenuCommand:target_type -> "USER" | "MESSAGE"
--
--   ContextMenuCommand:execute(ctx) -> response
--     Execute the command.

local class = require("core.class")

-- ContextMenuCommand class
local ContextMenuCommand = class("ContextMenuCommand")

function ContextMenuCommand.new(target_type, name, description)
    local self = {}
    setmetatable(self, {
        __index = ContextMenuCommand
    })

    self.id = ""
    self.target_type = target_type  -- "USER" or "MESSAGE"
    self.name = name
    self.description = description

    return self
end

-- Check if input matches this command
function ContextMenuCommand:matches(interaction)
    if self.target_type == "USER" then
        return interaction.target_id
    elseif self.target_type == "MESSAGE" then
        return interaction.target_id
    end
    return false
end

-- Get response type
function ContextMenuCommand:get_response_type()
    return "CONTEXT_MENU_RESPONSE"
end

return ContextMenuCommand
