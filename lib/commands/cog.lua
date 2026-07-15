-- lib/commands/cog.lua
-- Cog class for ext.commands
--
-- Cogs are tables with command methods and listeners.
--
-- Public Contract:
--   Cog.new(name) -> Cog
--     Creates a new Cog.
--
--   Cog:register(bot, prefix) -> nil
--     Registers the cog with the bot.
--
--   Cog:unregister() -> nil
--     Unregisters the cog.

local M = {}

-- Cog class
M.Cog = {
    -- Default commands and listeners
    commands = {},
    listeners = {},
}

-- Create a new Cog
function M.new(name)
    local cog = {
        name = name,
        commands = {},
        listeners = {},
    }
    setmetatable(cog, {
        __index = M.Cog
    })
    return cog
end

-- Register commands from cog methods
function M.Cog:register_commands(bot, prefix)
    -- Find all methods that start with 'command_'
    for method, func in pairs(self) do
        if method:sub(1, 8) == "command_" then
            local command_name = method:sub(9)
            local command_func = func

            -- Check for command description
            if type(command_func) == "table" then
                command_name = command_func.name or command_name
                command_func = command_func.func or func
            end

            -- Register the command
            bot:register_command(command_name, function(ctx, args)
                return command_func(ctx, args)
            end, prefix)
        end
    end
end

-- Register listeners from cog methods
function M.Cog:register_listeners(bot)
    -- Find all methods that start with 'on_'
    for method, func in pairs(self) do
        if method:sub(1, 3) == "on_" then
            local event_name = method:sub(4)
            local listener_func = func

            -- Register the listener
            bot:on(event_name, function(...)
                return listener_func(...)
            end)
        end
    end
end

return M
