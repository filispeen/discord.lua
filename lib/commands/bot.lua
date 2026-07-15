-- lib/commands/bot.lua
-- Bot class for ext.commands
--
-- Public Contract:
--   Bot.new(token, ratelimiter) -> Bot
--     Creates a new Bot instance.
--
--   Bot:register_command(name, func, prefix) -> nil
--     Registers a prefix command.
--
--   Bot:register_application_command(name, options) -> nil
--     Registers a slash command.
--
--   Bot:unregister_command(name) -> nil
--     Unregisters a command.
--
--   Bot:on(event, callback) -> self
--     Subscribe to an event.
--
--   Bot:emit(event, ...) -> self
--     Emit an event.
--
--   Bot:add_cog(cog) -> nil
--     Add a Cog to the bot.
--
--   Bot:remove_cog(cog) -> nil
--     Remove a Cog from the bot.
--
--   Bot:get_command(name) -> Command or nil
--     Get a command by name.
--
--   Bot:get_commands() -> table
--     Get all registered commands.
--
--   Bot:get_member(user_id) -> Member or nil
--     Get a guild member by ID.
--
--   Bot:get_user(user_id) -> User or nil
--     Get a user by ID.
--
--   Bot:get_channel(channel_id) -> Channel or nil
--     Get a channel by ID.
--
--   Bot:get_role(role_id) -> Role or nil
--     Get a role by ID.

local class = require("core.class")

-- Bot class
local Bot = class("Bot")

function Bot.new(token, ratelimiter)
    local self = {
        token = token,
        ratelimiter = ratelimiter or {},
        commands = {},  -- [name] = Command
        cogs = {},      -- [name] = Cog
        listeners = {}, -- [event] = {fn1, fn2, ...}
        http = nil,     -- HTTP client (created when needed)
        prefix = "!",
    }
    setmetatable(self, {
        __index = Bot
    })
    return self
end

-- Create HTTP client
function Bot:_create_http_client()
    local ratelimiter = require("http.ratelimiter")
    local client = require("http.client")

    local manager = ratelimiter.Manager.new()
    self.ratelimiter = manager

    local http_client = client.new(self.token, manager)
    self.http = http_client

    return http_client
end

-- Register a prefix command
function Bot:register_command(name, func, prefix)
    if not self.commands[name] then
        self.commands[name] = func
        self.prefixes[name] = prefix
    end
end

-- Register a slash command
function Bot:register_application_command(name, options)
    -- Store command for later sync
    if not self.application_commands then
        self.application_commands = {}
    end
    self.application_commands[name] = {
        name = name,
        options = options or {},
    }
end

-- Unregister a command
function Bot:unregister_command(name)
    self.commands[name] = nil
end

-- Subscribe to an event
function Bot:on(event, callback)
    if not self.listeners[event] then
        self.listeners[event] = {}
    end
    table.insert(self.listeners[event], callback)
    return self
end

-- Emit an event
function Bot:emit(event, ...)
    if self.listeners[event] then
        for _, callback in ipairs(self.listeners[event]) do
            callback(...)
        end
    end
    return self
end

-- Add a Cog to the bot
function Bot:add_cog(cog)
    if not self.cogs[cog.name] then
        self.cogs[cog.name] = cog
    end
end

-- Remove a Cog from the bot
function Bot:remove_cog(cog)
    self.cogs[cog.name] = nil
end

-- Get a command by name
function Bot:get_command(name)
    return self.commands[name]
end

-- Get all commands
function Bot:get_commands()
    return self.commands
end

-- Get a member by ID (placeholder - needs guild context)
function Bot:get_member(user_id)
    -- This would require guild context
    return nil
end

-- Get a user by ID (placeholder - needs API call)
function Bot:get_user(user_id)
    if self.http then
        local response = self.http:get("/users/" .. user_id)
        return response
    end
    return nil
end

-- Get a channel by ID (placeholder - needs guild context)
function Bot:get_channel(channel_id)
    return nil
end

-- Get a role by ID (placeholder - needs guild context)
function Bot:get_role(role_id)
    return nil
end

return Bot
