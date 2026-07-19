-- lib/commands/bot.lua
-- Bot class for ext.commands

local class = require("core.class")
local Embed = require("models.embed")
local CommandTree = require("interactions.command_tree")

local Bot = class('Bot')

-- Per-instance __index: falls through to Bot's methods for everything,
-- except "user", which reads live from self.client.user (set once the
-- READY payload arrives) so bot.user works the same way pycord's
-- Bot.user does, without needing to copy/sync the value on every ready.
local function bot_index(instance, key)
    if key == "user" then
        local client = rawget(instance, "client")
        return client and client.user or nil
    end
    return Bot[key]
end

function Bot.new(token, ratelimiter, intents)
    local self = setmetatable({}, { __index = bot_index })
    self.token = token
    self.ratelimiter = ratelimiter or {}
    self.intents = intents
    self.commands = {}
    self.command_descriptions = {}
    self.command_checks = {}
    self.cogs = {}
    self.listeners = {}
    self.http = nil
    self.prefixes = {}
    self.prefix = "!"
    self.application_commands = {}
    self.command_tree = CommandTree.new(nil)
    self.components = {}
    self.interactions = {}
    self.client = nil
    self.auto_sync_commands = true
    return self
end

-- Opt-in helper: registers a "help" command that replies with the output
-- of generate_help_text. Not called automatically from Bot.new, since that
-- would add an entry into self.commands that callers did not ask for.
function Bot:register_help_command()
    self:register_command("help", function(message)
        local args = message.content:match("^%S+%s+(.*)$")
        local text = self:generate_help_text(args)
        if message.reply then
            message:reply(text)
        end
    end, self.prefix, "Shows this message")
    return self
end

-- Registers a prefix command. description is optional and only used to
-- populate the generated help command; existing callers that only pass
-- (name, func, prefix) keep working unchanged. checks is an optional list
-- of check tables (see commands.checks / commands.cooldown), each with a
-- .func(ctx) that returns true/false or raises (e.g. CommandOnCooldown).
function Bot:register_command(name, func, prefix, description, checks)
    if not self.commands[name] then
        self.commands[name] = func
        self.prefixes[name] = prefix
        self.command_descriptions[name] = description or ""
        self.command_checks[name] = checks or {}
    end
end

-- Registers a slash command, building an ApplicationCommand and adding it
-- to the command_tree so a later sync_commands() call registers it with
-- Discord. options.description, options.options, options.guild_ids and
-- options.callback are all optional.
function Bot:register_application_command(name, options)
    options = options or {}

    if not self.application_commands then
        self.application_commands = {}
    end
    self.application_commands[name] = {
        name = name,
        options = options.options or {},
    }

    local ApplicationCommand = require("interactions.application_command")
    local cmd = ApplicationCommand.new(name, options.description or name, options.options)
    cmd.guild_ids = options.guild_ids
    cmd.callback = options.callback
    cmd.checks = options.checks or {}

    self.command_tree:add(cmd)
    return cmd
end

-- Fetches the application id if needed, then registers all pending
-- application commands with Discord. Must be called after connect().
function Bot:sync_commands()
    if not self.client then
        error("Bot:sync_commands called before connect()", 0)
    end

    local application_id = self.client:get_application_id()
    if not application_id then
        error("could not resolve application id for command sync", 0)
    end

    self.command_tree.http = self.http
    return self.command_tree:sync(application_id)
end

function Bot:unregister_command(name)
    self.commands[name] = nil
    self.prefixes[name] = nil
    self.command_descriptions[name] = nil
    self.command_checks[name] = nil
end

-- Runs every registered check for a command against ctx, in order.
-- Returns true if all checks pass. Lets check errors (e.g. CommandOnCooldown)
-- propagate to the caller, matching pycord's check-raises-on-failure model.
function Bot:run_checks(name, ctx)
    local checks = self.command_checks[name]
    if not checks then
        return true
    end

    for _, check in ipairs(checks) do
        if not check.func(ctx) then
            return false
        end
    end
    return true
end

function Bot:on(event, callback)
    if not self.listeners[event] then
        self.listeners[event] = {}
    end
    table.insert(self.listeners[event], callback)
    return self
end

-- Sugar for bot:on("message_create", callback). Fires for every message
-- the gateway sees, prefix commands included, not just unmatched ones.
function Bot:on_message(callback)
    return self:on("message_create", callback)
end

function Bot:emit(event, ...)
    if self.listeners[event] then
        for _, callback in ipairs(self.listeners[event]) do
            callback(...)
        end
    end
    return self
end

function Bot:add_cog(cog)
    if not self.cogs[cog.name] then
        self.cogs[cog.name] = cog
    end
end

function Bot:remove_cog(cog)
    self.cogs[cog.name] = nil
end

function Bot:get_command(name)
    return self.commands[name]
end

function Bot:get_commands()
    return self.commands
end

function Bot.get_member(_self, _user_id)
    return nil
end

function Bot:get_user(user_id)
    if self.client and self.client.rest then
        return self.client.rest:get_user(user_id)
    end
    if self.http then
        return self.http:get("/users/" .. user_id)
    end
    return nil
end

function Bot.get_channel(_self, _channel_id)
    return nil
end

function Bot.get_role(_self, _role_id)
    return nil
end

-- Returns the voice channel id a member is currently in, built from
-- VOICE_STATE_UPDATE dispatch events. nil if the member is not known to
-- be in voice (never seen, since left, or the gateway hasn't been
-- started yet). Requires the GUILD_VOICE_STATES intent.
function Bot:get_voice_channel_id(guild_id, user_id)
    if not self.client then
        return nil
    end
    return self.client:get_voice_channel_id(guild_id, user_id)
end

-- Convenience for prefix commands: the voice channel id the message's
-- author is currently in, in the message's guild. nil in DMs or if the
-- author is not in a voice channel.
function Bot:get_author_voice_channel_id(message)
    if not message or not message.guild_id or not message.author then
        return nil
    end
    return self:get_voice_channel_id(message.guild_id, message.author.id)
end

-- Registers a prefix command by name with its callback, mirrors register_command
-- but matches the README/examples calling convention: client:command(name, fn)
function Bot:command(name, func, description)
    self:register_command(name, func, self.prefix, description)
    return self
end

-- Registers a View (from ui.view) so its buttons/selects route through
-- Bot:interaction when an INTERACTION_CREATE dispatch matches a custom_id.
function Bot:component(view)
    table.insert(self.components, view)
    return self
end

-- Registers a callback for a specific custom_id, invoked when a component
-- interaction or modal submit with that custom_id is dispatched.
function Bot:interaction(custom_id, callback)
    self.interactions[custom_id] = callback
    return self
end

-- Dispatches an incoming interaction payload to the matching registered
-- callback, looked up by custom_id.
function Bot:dispatch_interaction(interaction)
    if not interaction then
        return false
    end

    if interaction.type == 4 then
        return self.command_tree:dispatch_autocomplete(interaction, self.client)
    end

    if interaction.type == 2 and interaction.data then
        local guild_id = interaction.guild_id
        local cmd = self.command_tree:get(interaction.data.name, guild_id)
        if cmd and cmd.callback then
            local slash = require("interactions.slash")
            local ctx = slash.new(interaction, self.client)

            local ok, err = pcall(function()
                if cmd.checks then
                    for _, check in ipairs(cmd.checks) do
                        if not check.func(ctx) then
                            return
                        end
                    end
                end
                cmd.callback(ctx)
            end)

            if not ok then
                self:emit("application_command_error", ctx, err)
            end
            return true
        end
    end

    local custom_id = interaction.custom_id
    if custom_id then
        local ComponentContext = require("interactions.component_context")
        local ctx = ComponentContext.new(interaction, self.client)

        for _, view in ipairs(self.components) do
            if not view.stopped then
                local item = view:find_item(custom_id)
                if item and item.callback then
                    item.callback(ctx)
                    return true
                end
            end
        end

        if self.interactions[custom_id] then
            self.interactions[custom_id](ctx)
            return true
        end
    end
    return false
end

-- Builds an Embed model, mirrors client:embed(...) used in examples.
function Bot.embed(_self, data)
    return Embed.new(data)
end

-- Edits a message via PATCH /channels/{channel_id}/messages/{message_id}.
-- guild_id is accepted for API symmetry with examples but is not part of the route.
function Bot:edit_message(_guild_id, channel_id, message_id, payload)
    if not self.http then
        error("Bot has no http client, call Bot:run() or Bot:connect() first", 0)
    end
    if self.client and self.client.rest then
        return self.client.rest:edit_message(channel_id, message_id, payload)
    end
    local endpoint = "/channels/" .. channel_id .. "/messages/" .. message_id
    return self.http:patch(endpoint, payload)
end

-- Connects the underlying gateway/http client without blocking, useful in tests.
function Bot:connect()
    local Client = require("models.client")
    self.client = Client.new(self.token, self.ratelimiter, self.intents)
    self.client:_create_http()
    self.http = self.client.http

    self.client:on("ready", function()
        if self.auto_sync_commands then
            self:sync_commands()
        end
        self:emit("ready")
    end)

    self.client:on("interaction_create", function(interaction)
        self:dispatch_interaction(interaction)
    end)

    self.client:on("message_create", function(message)
        self:dispatch_message(message)
        self:emit("message_create", message)
    end)

    -- Forward voice gateway events, needed by voice/Lavalink integrations
    -- to build the voiceUpdate payload.
    for _, event_name in ipairs({ "voice_state_update", "voice_server_update" }) do
        self.client:on(event_name, function(...)
            self:emit(event_name, ...)
        end)
    end

    -- Forward shard lifecycle events so bot:on("shard_ready", ...) and
    -- bot:event("shard_ready")(...) work the same way "ready" does.
    for _, event_name in ipairs({ "shard_ready", "shard_error", "shard_disconnect" }) do
        self.client:on(event_name, function(...)
            self:emit(event_name, ...)
        end)
    end

    return self
end

-- Builds a plain text help message. With no argument, lists every
-- registered command with its one line description, sorted by name.
-- With a command name, shows that command's description, prefix and
-- aliases (if it was registered through a Command object).
function Bot:generate_help_text(command_name)
    if command_name and command_name ~= "" then
        local func = self.commands[command_name]
        if not func then
            return "No command called \"" .. command_name .. "\" found."
        end

        local description = self.command_descriptions[command_name] or ""
        local prefix = self.prefixes[command_name] or self.prefix
        local lines = { prefix .. command_name }
        if description ~= "" then
            table.insert(lines, description)
        end
        return table.concat(lines, "\n")
    end

    local names = {}
    for name in pairs(self.commands) do
        table.insert(names, name)
    end
    table.sort(names)

    local lines = {}
    for _, name in ipairs(names) do
        local prefix = self.prefixes[name] or self.prefix
        local description = self.command_descriptions[name] or ""
        if description ~= "" then
            table.insert(lines, prefix .. name .. ", " .. description)
        else
            table.insert(lines, prefix .. name)
        end
    end

    return table.concat(lines, "\n")
end

-- Parses a prefix command out of an incoming Message and invokes its callback.
-- Requires the gateway to emit a message_create event with a Message-shaped
-- payload; see PROGRESS.md, gateway MESSAGE_CREATE dispatch is not wired yet.
function Bot:dispatch_message(message)
    if type(message.content) ~= "string" then
        return false
    end

    if message.content:sub(1, #self.prefix) ~= self.prefix then
        return false
    end

    local name = message.content:sub(#self.prefix + 1):match("^(%S+)")
    if not name then
        return false
    end

    local func = self.commands[name]
    if not func then
        return false
    end

    local ok, err = pcall(function()
        if not self:run_checks(name, message) then
            return
        end
        func(message)
    end)

    if not ok then
        self:emit("command_error", message, err)
    end

    return true
end

-- Connects and starts the gateway loop, mirrors client:run(token) in README/examples.
function Bot:run(token)
    if token then
        self.token = token
    end
    self:connect()
    self.client:start_gateway()
    return self
end

return Bot