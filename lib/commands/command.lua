-- lib/commands/command.lua
-- Command class for ext.commands
--
-- Commands are defined with description, usage, and options.

local M = {}

-- Command class
M.Command = {
    description = "",
    usage = "",
    example = "",
    name = "",
    aliases = {},
    checks = {},
}

-- Create a new Command
function M.new(name, description, usage)
    local command = {
        name = name or "",
        description = description or "",
        usage = usage or "",
        example = "",
        aliases = {},
        checks = {},
    }
    setmetatable(command, {
        __index = M.Command
    })
    return command
end

-- Add a check function
function M.Command:add_check(fn)
    table.insert(self.checks, fn)
    return self
end

-- Set example usage
function M.Command:example(example)
    self.example = example
    return self
end

-- Add an alias
function M.Command:add_alias(alias)
    table.insert(self.aliases, alias)
    return self
end

-- Get full command name including aliases
function M.Command:get_all_names()
    local names = { self.name }
    for _, alias in ipairs(self.aliases) do
        table.insert(names, alias)
    end
    return names
end

return M
