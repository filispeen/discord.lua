-- lib/interactions/slash_command_group.lua

local class = require("../core/class")
local ApplicationCommand = require("./application_command")

local SUB_COMMAND = 1
local SUB_COMMAND_GROUP = 2
local SlashCommandGroup = class("SlashCommandGroup")

local command_fields = {
    "name_localizations", "description_localizations", "default_member_permissions",
    "integration_types", "contexts", "nsfw", "handler",
}

local function copy_command_fields(target, source)
    for _, field in ipairs(command_fields) do
        if source[field] ~= nil then target[field] = source[field] end
    end
end

local function subcommand_option(cmd)
    local data = cmd:to_dict()
    return {
        type = SUB_COMMAND,
        name = data.name,
        name_localizations = data.name_localizations,
        description = data.description,
        description_localizations = data.description_localizations,
        options = data.options,
    }
end

function SlashCommandGroup.new(name, description, options)
    options = options or {}
    local self = setmetatable({}, SlashCommandGroup)
    self.name = name
    self.description = description or name
    self.type = ApplicationCommand.TYPE_CHAT_INPUT
    self.checks = options.checks or {}
    self.guild_ids = options.guild_ids
    self.subcommands = {}
    self.subgroups = {}
    copy_command_fields(self, options)
    return self
end

function SlashCommandGroup:command(name, description, callback, cmd_options)
    cmd_options = cmd_options or {}
    local cmd = ApplicationCommand.new(name, description or name, cmd_options.options)
    cmd.callback = callback
    cmd.guild_ids = self.guild_ids
    cmd.checks = cmd_options.checks or {}
    copy_command_fields(cmd, cmd_options)
    self.subcommands[name] = cmd
    return cmd
end

function SlashCommandGroup:create_subgroup(name, description, options)
    options = options or {}
    options.guild_ids = options.guild_ids or self.guild_ids
    local subgroup = SlashCommandGroup.new(name, description, options)
    self.subgroups[name] = subgroup
    return subgroup
end

function SlashCommandGroup:find(path)
    if not path or #path == 0 then return nil end
    local head = path[1]
    if #path == 1 then return self.subcommands[head] end
    local rest = {}
    for i = 2, #path do rest[#rest + 1] = path[i] end
    local subgroup = self.subgroups[head]
    return subgroup and subgroup:find(rest) or nil
end

function SlashCommandGroup:collect_checks()
    return self.checks
end

function SlashCommandGroup:to_dict()
    local options = {}
    for _, cmd in pairs(self.subcommands) do options[#options + 1] = subcommand_option(cmd) end
    for _, subgroup in pairs(self.subgroups) do
        local children = {}
        for _, cmd in pairs(subgroup.subcommands) do children[#children + 1] = subcommand_option(cmd) end
        options[#options + 1] = {
            type = SUB_COMMAND_GROUP,
            name = subgroup.name,
            name_localizations = subgroup.name_localizations,
            description = subgroup.description,
            description_localizations = subgroup.description_localizations,
            options = children,
        }
    end
    local result = {
        name = self.name,
        description = self.description,
        type = ApplicationCommand.TYPE_CHAT_INPUT,
        options = options,
    }
    copy_command_fields(result, self)
    if result.default_member_permissions ~= nil then
        result.default_member_permissions = tostring(result.default_member_permissions)
    end
    return result
end

return SlashCommandGroup
