-- lib/ext/bridge/bridge_group.lua
-- BridgeGroup: a command group that works as both a prefix command group
-- and a slash command group, contract mirrors pycord's ext.bridge
-- bridge_group / BridgeCommandGroup and the @bridge.map_to decorator.
--
-- Public Contract:
--   BridgeGroup.new(bot, name, options) -> bridge_group
--     bot: the Bot instance to register commands on
--     name: string
--     options.description: string
--     options.invoke_without_command: boolean or nil - if true and
--       map_to() was used, calling the bare prefix command name (with no
--       subcommand) runs the mapped callback, mirrors pycord's
--       commands.group(invoke_without_command=True).
--     options.guild_ids / options.checks: forwarded to the slash side.
--
--   bridge_group:command(name, options) -> ApplicationCommand
--     Registers a subcommand under this group, on both the prefix side
--     (as "groupname name") and the slash side (as a SlashCommandGroup
--     subcommand). options.callback receives a BridgeContext.
--
--   bridge_group:map_to(name, callback) -> self
--     Sets this group's own bare invocation (the callback passed to
--     bridge_group() itself) to also be reachable as a slash subcommand
--     called `name`, since Discord's API has no concept of invoking a
--     slash command group directly. On the prefix side this is a no-op,
--     the bare group name already invokes callback directly.

local class = require("core.class")
local SlashCommandGroup = require("interactions.slash_command_group")
local BridgeContext = require("ext.bridge.bridge_context")

local BridgeGroup = class("BridgeGroup")

function BridgeGroup.new(bot, name, options)
    options = options or {}

    local self = setmetatable({}, BridgeGroup)
    self.bot = bot
    self.name = name
    self.description = options.description or name
    self.invoke_without_command = options.invoke_without_command or false
    self.callback = options.callback

    self.slash_group = SlashCommandGroup.new(name, self.description, {
        guild_ids = options.guild_ids,
        checks = options.checks,
    })
    bot:register_slash_command_group(self.slash_group)

    if self.callback and self.invoke_without_command then
        bot:register_command(name, function(message)
            local ctx = BridgeContext.new(message, "prefix")
            self.callback(ctx)
        end, bot.prefix, self.description, options.checks)
    end

    return self
end

function BridgeGroup:command(name, options)
    options = options or {}
    local callback = options.callback

    self.bot:register_command(self.name .. " " .. name, function(message)
        local ctx = BridgeContext.new(message, "prefix")
        callback(ctx)
    end, self.bot.prefix, options.description, options.checks)

    return self.slash_group:command(name, options.description or name, function(slash_ctx)
        local ctx = BridgeContext.new(slash_ctx, "app")
        callback(ctx)
    end, { options = options.options, checks = options.checks })
end

-- Mirrors @bridge.map_to(name): makes this group's own bare callback
-- (the one passed to Bot:bridge_group) reachable as `/<group> <name>`,
-- since a slash command group cannot be invoked directly.
function BridgeGroup:map_to(name)
    if not self.callback then
        error("map_to requires the group to have been created with a callback", 0)
    end

    local callback = self.callback
    return self.slash_group:command(name, self.description, function(slash_ctx)
        local ctx = BridgeContext.new(slash_ctx, "app")
        callback(ctx)
    end)
end

return BridgeGroup
