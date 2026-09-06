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

local class = require("../core/class")

local CommandTree = class("CommandTree")

function CommandTree.new(http)
    local self = {
        http = http,
        commands = {},
    }
    setmetatable(self, { __index = CommandTree })
    return self
end

local function shared_scope(first, second)
    if first.guild_ids == nil or second.guild_ids == nil then
        if first.guild_ids == nil and second.guild_ids == nil then
            return "global"
        end
        return nil
    end

    for _, first_guild_id in ipairs(first.guild_ids) do
        for _, second_guild_id in ipairs(second.guild_ids) do
            if first_guild_id == second_guild_id then
                return "guild " .. tostring(first_guild_id)
            end
        end
    end
end

function CommandTree:add(command)
    local command_type = command.type or 1
    for _, existing in ipairs(self.commands) do
        local scope = shared_scope(existing, command)
        if scope and existing.name == command.name and (existing.type or 1) == command_type then
            error(("Duplicate application command %q (type %d) in the %s scope")
                :format(command.name, command_type, scope), 0)
        end
    end
    table.insert(self.commands, command)
    return self
end

function CommandTree:get(name, guild_id)
    for _, cmd in ipairs(self.commands) do
        if cmd.name == name then
            if cmd.guild_ids == nil then
                return cmd
            end
            if guild_id ~= nil then
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
            or (opt.description or "") ~= (remote_opt.description or "")
            or opt.type ~= remote_opt.type
            or (opt.required or false) ~= (remote_opt.required or false)
            or (opt.autocomplete or false) ~= (remote_opt.autocomplete or false)
        then
            return false
        end
    end

    return true
end

local function command_key(command)
    return tostring(command.type or 1) .. ":" .. command.name
end

-- Synchronizes one scope without replacing its entire command set. Existing
-- command IDs are retained; only missing, changed, and stale commands are
-- created, updated, and deleted respectively.
function CommandTree:_register(endpoint, commands)
    local local_dicts = {}
    local local_by_key = {}
    for i, cmd in ipairs(commands) do
        local_dicts[i] = cmd:to_dict()
        local_by_key[command_key(local_dicts[i])] = local_dicts[i]
    end

    local remote_dicts = self.http:get(endpoint) or {}
    local remote_by_key = {}
    for _, remote_dict in ipairs(remote_dicts) do
        remote_by_key[command_key(remote_dict)] = remote_dict
    end

    for key, remote_dict in pairs(remote_by_key) do
        if not local_by_key[key] then
            self.http:delete(endpoint .. "/" .. remote_dict.id)
        end
    end

    local result = {}
    for i, local_dict in ipairs(local_dicts) do
        local remote_dict = remote_by_key[command_key(local_dict)]
        if not remote_dict then
            result[i] = self.http:post(endpoint, local_dict)
        elseif commands_equal(local_dict, remote_dict) then
            result[i] = remote_dict
        else
            result[i] = self.http:patch(endpoint .. "/" .. remote_dict.id, local_dict)
        end
    end

    return result
end

-- Registers all pending commands by diffing each scope against Discord.
-- Commands no longer registered locally are deleted without clearing others.
function CommandTree:sync(application_id)
    local global_commands, guild_commands = self:_partition()

    local result = {
        global = {},
        guilds = {},
    }

    local global_endpoint = "/applications/" .. application_id .. "/commands"
    result.global = self:_register(
        global_endpoint,
        global_commands
    )

    for guild_id, commands in pairs(guild_commands) do
        local guild_endpoint = "/applications/" .. application_id .. "/guilds/" .. guild_id .. "/commands"
        result.guilds[guild_id] = self:_register(
            guild_endpoint,
            commands
        )
    end

    return result
end

-- Walks interaction.data.options collecting SUB_COMMAND (1) / SUB_COMMAND_GROUP
-- (2) names in order, stopping at the first non-group option node. Shared by
-- both dispatch_autocomplete and resolve so a nested "math add" or
-- "greetings international aloha" style path is parsed identically for both.
-- Returns the path (array of names) and the innermost options list (the
-- flat list belonging to whichever subcommand the path bottomed out at).
local function walk_group_path(options)
    local path = {}
    while options and #options > 0 do
        local opt = options[1]
        if opt.type == 1 or opt.type == 2 then
            table.insert(path, opt.name)
            options = opt.options
        else
            break
        end
    end
    return path, options
end

-- Dispatches an APPLICATION_COMMAND_AUTOCOMPLETE interaction to the
-- matching command's autocomplete callback for the focused option.
-- The callback receives an AutocompleteContext (ctx.value, ctx.options),
-- mirroring pycord's AutocompleteContext contract. Handles autocomplete on
-- a plain command as well as one fired from inside a SlashCommandGroup
-- subcommand or subgroup subcommand, walking the same SUB_COMMAND (1) /
-- SUB_COMMAND_GROUP (2) nesting that resolve() does for real invocations.
function CommandTree:dispatch_autocomplete(interaction, client)
    local data = interaction and interaction.data
    if not data or not data.options then
        return false
    end

    local top = self:get(data.name, interaction.guild_id)
    if not top then
        return false
    end

    local cmd, focused_options
    if top.find then
        local path, options = walk_group_path(data.options)
        cmd = top:find(path)
        focused_options = options
    else
        cmd = top
        focused_options = data.options
    end

    if not cmd or not cmd.autocomplete_callbacks then
        return false
    end

    local focused
    for _, opt in ipairs(focused_options or {}) do
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

    local AutocompleteContext = require("./autocomplete_context")
    local ctx = AutocompleteContext.new(interaction, client, focused.name, cmd)
    callback(ctx)
    return true
end

-- Resolves an APPLICATION_COMMAND interaction (type 2) down to the actual
-- ApplicationCommand that should run, and the ordered list of checks that
-- must pass first (group checks before subgroup checks before the command's
-- own checks, outermost first). Handles plain commands, one level of
-- subcommand nesting, and two levels (group -> subgroup -> subcommand).
-- Returns nil, {} if nothing matches.
function CommandTree:resolve(interaction)
    local data = interaction and interaction.data
    if not data then
        return nil, {}
    end

    local top = self:get(data.name, interaction.guild_id)
    if not top then
        return nil, {}
    end

    -- Plain ApplicationCommand: no group traversal needed.
    if not top.find then
        return top, top.checks or {}
    end

    -- SlashCommandGroup: walk interaction.data.options to find the
    -- SUB_COMMAND (1) or SUB_COMMAND_GROUP (2) path down to the command.
    local path = walk_group_path(data.options)

    local resolved = top:find(path)
    if not resolved then
        return nil, {}
    end

    local checks = {}
    for _, check in ipairs(top:collect_checks()) do
        table.insert(checks, check)
    end
    for _, check in ipairs(resolved.checks or {}) do
        table.insert(checks, check)
    end

    return resolved, checks
end

return CommandTree
