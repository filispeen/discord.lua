-- lib/commands/bot.lua
-- Bot class for ext.commands

local class = require("core.class")

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

function Bot:get_member(user_id)
    return nil
end

function Bot:get_user(user_id)
    if self.http then
        local response = self.http:get("/users/" .. user_id)
        return response
    end
    return nil
end

function Bot:get_channel(channel_id)
    return nil
end

function Bot:get_role(role_id)
    return nil
end

return Bot