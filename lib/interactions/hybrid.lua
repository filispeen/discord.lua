-- lib/interactions/hybrid.lua
-- Hybrid command class for ext.commands
--
-- Hybrid commands are defined once and work as both prefix commands
-- and application commands.

local class = require("core.class")

-- HybridCommand class
local HybridCommand = class("HybridCommand")

function HybridCommand.new(name, description, func, options)
    local self = {}
    setmetatable(self, {
        __index = HybridCommand
    })

    self.id = ""
    self.name = name
    self.description = description
    self.func = func
    self.options = options or {}
    self.prefix = ""  -- Default prefix
    self.aliases = {}

    return self
end

-- Add an alias
function HybridCommand:add_alias(alias)
    table.insert(self.aliases, alias)
    return self
end

-- Set prefix
function HybridCommand:set_prefix(prefix)
    self.prefix = prefix
    return self
end

-- Execute the command
function HybridCommand:execute(ctx, args)
    return self.func(ctx, args)
end

-- Check if input matches this command
function HybridCommand:matches(input)
    for _, name in ipairs({ self.name, unpack(self.aliases) }) do
        if input:lower():find(name:lower(), 1, true) then
            return true
        end
    end
    return false
end

-- Check exact match
function HybridCommand:exact_match(input)
    for _, name in ipairs({ self.name, unpack(self.aliases) }) do
        if input:lower() == name:lower() then
            return true
        end
    end
    return false
end

-- Get all command names
function HybridCommand:get_all_names()
    local names = { self.name }
    for _, alias in ipairs(self.aliases) do
        table.insert(names, alias)
    end
    return names
end

-- Convert to application command format
function HybridCommand:to_application_command()
    local cmd = {
        name = self.name,
        description = self.description,
        options = self.options or {},
    }
    return cmd
end

return HybridCommand
