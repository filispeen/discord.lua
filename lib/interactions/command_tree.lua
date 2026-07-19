-- lib/interactions/command_tree.lua
-- Application command tree, tracks pending commands and syncs them with
-- the Discord API.
--
-- Public Contract:
--   CommandTree.new(http) -> CommandTree
--     http: table, an http.client instance used to reach the Discord API.
--
--   CommandTree:add(command) -> self
--     Registers an ApplicationCommand to be synced.
--
--   CommandTree:get(name, guild_id) -> ApplicationCommand or nil
--     Looks up a pending command by name, optionally scoped to a guild.
--
--   CommandTree:sync(application_id) -> table
--     Diffs pending commands against what Discord currently has registered
--     and calls PUT only when the set has actually changed, global commands
--     via PUT /applications/{id}/commands, guild commands via
--     PUT /applications/{id}/guilds/{guild_id}/commands.
--     Returns a table with keys global and guilds, each a list of the
--     command dicts returned by Discord.

local class = require("core.class")

local CommandTree = class("CommandTree")

function CommandTree.new(http)
    local self = {
        http = http,
        commands = {},
    }
    setmetatable(self, { __index = CommandTree })
    return self
end

function CommandTree:add(command)
    table.insert(self.commands, command)
    return self
end

function CommandTree:get(name, guild_id)
    for _, cmd in ipairs(self.commands) do
        if cmd.name == name then
            if guild_id == nil and cmd.guild_ids == nil then
                return cmd
            end
            if guild_id ~= nil and cmd.guild_ids ~= nil then
                for _, gid in ipairs(cmd.guild_ids) do
                    if gid == guild_id then
                        return cmd
                    end
                end
            end
        end
    end
    return nil
end

-- Splits pending commands into global ones and a map of guild_id -> commands.
function CommandTree:_partition()
    local global_commands = {}
    local guild_commands = {}

    for _, cmd in ipairs(self.commands) do
        if cmd.guild_ids == nil then
            table.insert(global_commands, cmd)
        else
            for _, guild_id in ipairs(cmd.guild_ids) do
                guild_commands[guild_id] = guild_commands[guild_id] or {}
                table.insert(guild_commands[guild_id], cmd)
            end
        end
    end

    return global_commands, guild_commands
end

-- Compares a locally built command dict against a remote one, ignoring
-- fields that Discord adds server side (id, application_id, version, etc).
local function commands_equal(local_dict, remote_dict)
    if local_dict.name ~= remote_dict.name then
        return false
    end
    if (local_dict.description or "") ~= (remote_dict.description or "") then
        return false
    end
    if (local_dict.type or 1) ~= (remote_dict.type or 1) then
        return false
    end

    local local_options = local_dict.options or {}
    local remote_options = remote_dict.options or {}
    if #local_options ~= #remote_options then
        return false
    end

    for i, opt in ipairs(local_options) do
        local remote_opt = remote_options[i]
        if not remote_opt
            or opt.name ~= remote_opt.name
            or opt.type ~= remote_opt.type
            or (opt.required or false) ~= (remote_opt.required or false)
            or (opt.autocomplete or false) ~= (remote_opt.autocomplete or false)
        then
            return false
        end
    end

    return true
end

-- Returns true if the local set of commands differs from what Discord has,
-- either in count, names present, or any field on a matching command.
local function needs_update(local_dicts, remote_dicts)
    if #local_dicts ~= #remote_dicts then
        return true
    end

    local remote_by_name = {}
    for _, remote_dict in ipairs(remote_dicts) do
        remote_by_name[remote_dict.name] = remote_dict
    end

    for _, local_dict in ipairs(local_dicts) do
        local remote_dict = remote_by_name[local_dict.name]
        if not remote_dict or not commands_equal(local_dict, remote_dict) then
            return true
        end
    end

    return false
end

-- Registers a set of commands at the given endpoint, but only issues the
-- PUT if the local set differs from what Discord already has, since a bulk
-- overwrite PUT replaces the entire command set on that scope.
function CommandTree:_register(endpoint, commands)
    local local_dicts = {}
    for i, cmd in ipairs(commands) do
        local_dicts[i] = cmd:to_dict()
    end

    local remote_dicts = self.http:get(endpoint) or {}

    if not needs_update(local_dicts, remote_dicts) then
        return remote_dicts
    end

    return self.http:put(endpoint, local_dicts)
end

-- Registers all pending commands with Discord: global commands via a single
-- bulk overwrite, and each guild's commands via their own bulk overwrite.
-- Skips the PUT call entirely for a scope whose commands already match.
function CommandTree:sync(application_id)
    local global_commands, guild_commands = self:_partition()

    local result = {
        global = {},
        guilds = {},
    }

    result.global = self:_register(
        "/applications/" .. application_id .. "/commands",
        global_commands
    )

    for guild_id, commands in pairs(guild_commands) do
        result.guilds[guild_id] = self:_register(
            "/applications/" .. application_id .. "/guilds/" .. guild_id .. "/commands",
            commands
        )
    end

    return result
end

-- Dispatches an APPLICATION_COMMAND_AUTOCOMPLETE interaction to the
-- matching command's autocomplete callback for the focused option.
-- The callback receives an AutocompleteContext (ctx.value, ctx.options),
-- mirroring pycord's AutocompleteContext contract.
function CommandTree:dispatch_autocomplete(interaction, client)
    local data = interaction and interaction.data
    if not data or not data.options then
        return false
    end

    local cmd = self:get(data.name, interaction.guild_id)
    if not cmd then
        return false
    end

    local focused
    for _, opt in ipairs(data.options) do
        if opt.focused then
            focused = opt
            break
        end
    end
    if not focused then
        return false
    end

    local callback = cmd.autocomplete_callbacks[focused.name]
    if not callback then
        return false
    end

    local AutocompleteContext = require("interactions.autocomplete_context")
    local ctx = AutocompleteContext.new(interaction, client, focused.name, cmd)
    callback(ctx)
    return true
end

return CommandTree
