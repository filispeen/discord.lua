-- lib/commands/bot.lua
-- Bot class for ext.commands

local class = require("core.class")
local Embed = require("models.embed")

local Bot = class('Bot')

function Bot.new(token, ratelimiter)
    local self = setmetatable({}, Bot)
    self.token = token
    self.ratelimiter = ratelimiter or {}
    self.commands = {}
    self.cogs = {}
    self.listeners = {}
    self.http = nil
    self.prefixes = {}
    self.prefix = "!"
    self.application_commands = {}
    self.components = {}
    self.interactions = {}
    self.client = nil
    return self
end

function Bot:register_command(name, func, prefix)
    if not self.commands[name] then
        self.commands[name] = func
        self.prefixes[name] = prefix
    end
end

function Bot:register_application_command(name, options)
    if not self.application_commands then
        self.application_commands = {}
    end
    self.application_commands[name] = {
        name = name,
        options = options or {},
    }
end

function Bot:unregister_command(name)
    self.commands[name] = nil
    self.prefixes[name] = nil
end

function Bot:on(event, callback)
    if not self.listeners[event] then
        self.listeners[event] = {}
    end
    table.insert(self.listeners[event], callback)
    return self
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
    if self.http then
        local response = self.http:get("/users/" .. user_id)
        return response
    end
    return nil
end

function Bot.get_channel(_self, _channel_id)
    return nil
end

function Bot.get_role(_self, _role_id)
    return nil
end

-- Registers a prefix command by name with its callback, mirrors register_command
-- but matches the README/examples calling convention: client:command(name, fn)
function Bot:command(name, func)
    self:register_command(name, func, self.prefix)
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
    local custom_id = interaction and interaction.custom_id
    if custom_id and self.interactions[custom_id] then
        self.interactions[custom_id](interaction)
        return true
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
        error("Bot has no http client, call Bot:run() or Bot:connect() first")
    end
    local endpoint = "/channels/" .. channel_id .. "/messages/" .. message_id
    return self.http:patch(endpoint, payload)
end

-- Connects the underlying gateway/http client without blocking, useful in tests.
function Bot:connect()
    local Client = require("models.client")
    self.client = Client.new(self.token, self.ratelimiter)
    self.client:_create_http()
    self.http = self.client.http

    self.client:on("ready", function()
        self:emit("ready")
    end)

    self.client:on("interaction_create", function(interaction)
        self:dispatch_interaction(interaction)
    end)

    self.client:on("message_create", function(message)
        self:dispatch_message(message)
    end)

    return self
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

    func(message)
    return true
end

-- Connects and starts the gateway loop, mirrors client:run() in README/examples.
function Bot:run()
    self:connect()
    self.client:start_gateway()
    return self
end

return Bot