-- lib/ext/bridge/bridge_context.lua
-- BridgeContext: a unified context for commands registered through
-- Bot:bridge_command(), contract mirrors pycord discord.ext.bridge.BridgeContext.
--
-- Public Contract:
--   BridgeContext.new(source, kind) -> ctx
--     source: either the raw prefix Message (kind = "prefix") or a
--       SlashCommandContext (kind = "app")
--     kind: "prefix" or "app"
--
--   ctx.is_app -> boolean
--     True when this invocation came from a slash command.
--
--   ctx.author -> User
--   ctx.guild -> Guild or nil
--   ctx.channel -> Channel or nil
--   ctx.bot -> Client
--     Same shape regardless of invocation source.
--
--   ctx:respond(content, opts) -> result
--     Sends the command's reply. On the app path this is the interaction
--     response (or an edit, if a response was already sent, matching
--     pycord's ctx.respond auto-editing after the first call). On the
--     prefix path this is Message:reply.
--
--   ctx:defer() -> result
--     App path: acknowledges the interaction (DEFERRED_CHANNEL_MESSAGE_WITH_SOURCE).
--     Prefix path: a no-op, since prefix commands have no ack window.
--
--   ctx.followup -> table with :send(content, opts)
--     App path: sends a followup message via the webhook endpoint.
--     Prefix path: :send falls back to Message:reply, mirrors ctx.author:send
--     used in the bridge_commands.py example as the non-app equivalent.

local class = require("core.class")

local BridgeContext = class("BridgeContext")

function BridgeContext.new(source, kind)
    local self = setmetatable({}, BridgeContext)

    self._source = source
    self.is_app = (kind == "app")
    self._responded = false

    if self.is_app then
        self.author = source.author
        self.guild = source.guild
        self.channel = source.channel
        self.bot = source.bot
        self.args = source.args
    else
        self.author = source.author
        self.guild = source.guild
        self.channel = source.channel
        self.bot = source.bot
        self.args = {}
    end

    self.followup = {
        send = function(_self_followup, content, opts)
            return self:_followup_send(content, opts)
        end,
    }

    return self
end

function BridgeContext:respond(content, opts)
    if self.is_app then
        if self._responded then
            return self._source:edit(content, opts)
        end
        self._responded = true
        return self._source:respond(content, opts)
    end

    self._responded = true
    return self._source:reply(content)
end

-- Alias, mirrors pycord's ctx.reply / ctx.respond overlap on ApplicationContext.
function BridgeContext:reply(content, opts)
    return self:respond(content, opts)
end

function BridgeContext:defer()
    if not self.is_app then
        return nil
    end
    if not self.bot or not self.bot.rest then
        error("BridgeContext has no rest client attached, cannot defer", 0)
    end

    self._responded = true
    return self.bot.rest:create_interaction_response(
        self._source.interaction_id,
        self._source.interaction_token,
        { type = 5 }
    )
end

function BridgeContext:_followup_send(content, opts)
    if self.is_app then
        if not self.bot or not self.bot.rest then
            error("BridgeContext has no rest client attached, cannot send a followup", 0)
        end

        local payload = type(content) == "table" and content or { content = content }
        if opts and opts.ephemeral then
            payload.flags = 64
        end
        if opts and opts.embeds then
            payload.embeds = opts.embeds
        end
        if opts and opts.components then
            payload.components = opts.components
        end

        local endpoint = "/webhooks/" .. tostring(self.bot.application_id)
            .. "/" .. tostring(self._source.interaction_token)
        return self.bot.rest:post(endpoint, payload)
    end

    return self._source:reply(content)
end

return BridgeContext
