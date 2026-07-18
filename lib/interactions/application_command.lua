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
--
--   ApplicationCommand:to_dict() -> table
--     Serializes the command to the Discord API application command schema,
--     used by interactions.command_tree for registration and diffing.

local class = require("core.class")

-- ApplicationCommand class
local ApplicationCommand = class("ApplicationCommand")

-- Discord application command types
ApplicationCommand.TYPE_CHAT_INPUT = 1
ApplicationCommand.TYPE_USER = 2
ApplicationCommand.TYPE_MESSAGE = 3

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
    self.type = ApplicationCommand.TYPE_CHAT_INPUT
    self.guild_ids = nil
    self.autocomplete_callbacks = {}
    self.callback = nil

    return self
end

-- Registers an autocomplete callback for a specific option name.
function ApplicationCommand:set_autocomplete(option_name, callback)
    self.autocomplete_callbacks[option_name] = callback
    return self
end

-- Serializes to the Discord API application command schema.
function ApplicationCommand:to_dict()
    local dict = {
        name = self.name,
        description = self.description,
        type = self.type,
    }

    if self.type == ApplicationCommand.TYPE_CHAT_INPUT and self.options and #self.options > 0 then
        local options = {}
        for i, opt in ipairs(self.options) do
            options[i] = {
                type = opt.type,
                name = opt.name,
                description = opt.description,
                required = opt.required or false,
                choices = opt.choices,
                autocomplete = self.autocomplete_callbacks[opt.name] ~= nil or opt.autocomplete or nil,
            }
        end
        dict.options = options
    end

    return dict
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
