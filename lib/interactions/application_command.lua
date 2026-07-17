-- lib/interactions/application_command.lua
-- Application command interaction handler
--
-- Public Contract:
--   ApplicationCommand.new(name, description, options) -> ApplicationCommand
--
--   ApplicationCommand:options -> table
--     Command options (choices, autocomplete, etc.)
--
--   ApplicationCommand:execute(ctx) -> response
--     Execute the command and return response.

local class = require("core.class")

-- ApplicationCommand class
local ApplicationCommand = class("ApplicationCommand")

function ApplicationCommand.new(name, description, options)
    local self = {}
    setmetatable(self, {
        __index = ApplicationCommand
    })

    self.id = ""
    self.name = name
    self.description = description
    self.options = options or {}
    self.aliases = {}

    return self
end

-- Add an alias
function ApplicationCommand:add_alias(alias)
    table.insert(self.aliases, alias)
    return self
end

-- Get all command names
function ApplicationCommand:get_all_names()
    local names = { self.name }
    for _, alias in ipairs(self.aliases) do
        table.insert(names, alias)
    end
    return names
end

-- Check if input matches any command name
function ApplicationCommand:matches(input)
    for _, name in ipairs(self:get_all_names()) do
        if input:lower():find(name:lower(), 1, true) then
            return true
        end
    end
    return false
end

-- Check if input exactly matches a command name
function ApplicationCommand:exact_match(input)
    input = input:lower()
    for _, name in ipairs(self:get_all_names()) do
        if name:lower() == input then
            return true
        end
    end
    return false
end

-- Get response type for this command
function ApplicationCommand.get_response_type(_self)
    return "APPLICATION_COMMAND_RESPONSE"
end

return ApplicationCommand
