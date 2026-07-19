-- lib/interactions/slash_command_group.lua
-- SlashCommandGroup: application command group, contract mirrors pycord
-- discord.SlashCommandGroup / commands.SlashCommandGroup.
--
-- Public Contract:
--   SlashCommandGroup.new(name, description, options) -> group
--     name: string
--     description: string
--     options.checks: optional list of check tables (see commands.checks /
--       commands.cooldown), enforced against ctx before ANY subcommand or
--       subgroup callback under this group runs.
--     options.guild_ids: optional list of guild id strings, scopes the
--       whole group (and every subcommand/subgroup under it) to those guilds.
--
--   group:command(name, description, callback, options) -> ApplicationCommand
--     Registers a direct subcommand of this group. options.options is the
--     subcommand's own option list (choices, autocomplete, etc, same shape
--     as ApplicationCommand options).
--
--   group:create_subgroup(name, description, options) -> SlashCommandGroup
--     Creates and attaches a nested subgroup (one level of nesting, matches
--     Discord's own two-level limit: group -> subgroup -> subcommand).
--
--   group:to_dict() -> table
--     Serializes to the Discord API application command schema: a
--     TYPE_CHAT_INPUT command whose options are SUB_COMMAND (type 1) or
--     SUB_COMMAND_GROUP (type 2) entries, used by interactions.command_tree
--     for registration and diffing.
--
--   group:find(path) -> ApplicationCommand or SlashCommandGroup or nil
--     path: array of name segments after the group name itself, e.g.
--     for "/math add" (group "math", subcommand "add") path is {"add"};
--     for "/greetings international aloha" path is {"international", "aloha"}.
--     Used by command_tree/bot dispatch to resolve a nested interaction
--     call down to the ApplicationCommand that should actually run.

local class = require("core.class")
local ApplicationCommand = require("interactions.application_command")

local SUB_COMMAND = 1
local SUB_COMMAND_GROUP = 2

local SlashCommandGroup = class("SlashCommandGroup")

function SlashCommandGroup.new(name, description, options)
    options = options or {}

    local self = setmetatable({}, SlashCommandGroup)
    self.name = name
    self.description = description or name
    self.checks = options.checks or {}
    self.guild_ids = options.guild_ids
    self.subcommands = {}
    self.subgroups = {}

    return self
end

-- Registers a direct subcommand under this group. Mirrors pycord's
-- @group.command() decorator. The returned ApplicationCommand inherits
-- the group's guild_ids so command_tree scopes it the same way.
function SlashCommandGroup:command(name, description, callback, cmd_options)
    cmd_options = cmd_options or {}

    local cmd = ApplicationCommand.new(name, description or name, cmd_options.options)
    cmd.callback = callback
    cmd.guild_ids = self.guild_ids
    cmd.checks = cmd_options.checks or {}

    self.subcommands[name] = cmd
    return cmd
end

-- Creates and attaches a nested subgroup, one level deep (Discord allows
-- group -> subgroup -> subcommand, no further nesting). Mirrors pycord's
-- group.create_subgroup(name, description).
function SlashCommandGroup:create_subgroup(name, description, options)
    options = options or {}
    options.guild_ids = options.guild_ids or self.guild_ids

    local subgroup = SlashCommandGroup.new(name, description, options)
    self.subgroups[name] = subgroup
    return subgroup
end

-- Resolves a dotted/segmented path of subcommand or subgroup names down to
-- the ApplicationCommand that should handle the interaction. Returns nil if
-- no match exists at any level.
function SlashCommandGroup:find(path)
    if not path or #path == 0 then
        return nil
    end

    local head = path[1]
    local rest = {}
    for i = 2, #path do
        rest[#rest + 1] = path[i]
    end

    if #rest == 0 then
        return self.subcommands[head]
    end

    local subgroup = self.subgroups[head]
    if not subgroup then
        return nil
    end
    return subgroup:find(rest)
end

-- Collects every check that should run before a subcommand/subgroup
-- callback fires: this group's own checks, in order, so a group-level
-- check (e.g. owner-only) enforces across all of its subcommands.
function SlashCommandGroup:collect_checks()
    return self.checks
end

function SlashCommandGroup:to_dict()
    local options = {}

    for _, cmd in pairs(self.subcommands) do
        local cmd_dict = cmd:to_dict()
        table.insert(options, {
            type = SUB_COMMAND,
            name = cmd_dict.name,
            description = cmd_dict.description,
            options = cmd_dict.options,
        })
    end

    for _, subgroup in pairs(self.subgroups) do
        local sub_options = {}
        for _, cmd in pairs(subgroup.subcommands) do
            local cmd_dict = cmd:to_dict()
            table.insert(sub_options, {
                type = SUB_COMMAND,
                name = cmd_dict.name,
                description = cmd_dict.description,
                options = cmd_dict.options,
            })
        end

        table.insert(options, {
            type = SUB_COMMAND_GROUP,
            name = subgroup.name,
            description = subgroup.description,
            options = sub_options,
        })
    end

    return {
        name = self.name,
        description = self.description,
        type = ApplicationCommand.TYPE_CHAT_INPUT,
        options = options,
    }
end

return SlashCommandGroup
