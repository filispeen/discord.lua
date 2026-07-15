-- lib/commands/group.lua
-- Group class for ext.commands
--
-- Groups organize commands under a single prefix command.

local M = {}

-- Group class
M.Group = {
    description = "",
    usage = "",
    example = "",
    name = "",
    aliases = {},
}

-- Create a new Group
function M.new(name, description)
    local group = {
        name = name or "",
        description = description or "",
        usage = "",
        example = "",
        aliases = {},
    }
    setmetatable(group, {
        __index = M.Group
    })
    return group
end

-- Add an alias
function M.Group:add_alias(alias)
    table.insert(self.aliases, alias)
    return self
end

-- Add a subcommand
function M.Group:add_subcommand(name, description)
    if not self.subcommands then
        self.subcommands = {}
    end
    self.subcommands[name] = {
        name = name,
        description = description or "",
    }
    return self
end

-- Get full command name
function M.Group:get_full_name(subcommand)
    return self.name .. " " .. (subcommand or self.name)
end

return M
