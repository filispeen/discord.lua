-- lib/interactions/component_context.lua
-- Response helper for MESSAGE_COMPONENT interactions (buttons, selects).
-- Mirrors the parts of pycord's discord.Interaction used by component
-- callbacks: responding with a new message, updating the message the
-- component is attached to, or deferring.
--
-- Public Contract:
--   ComponentContext.new(interaction, client) -> ComponentContext
--     Wraps a raw MESSAGE_COMPONENT interaction payload. All fields from
--     the raw interaction (message, member, guild_id, etc) are copied
--     onto the context. custom_id, component_type and values are hoisted
--     from interaction.data onto the context's top level (ctx.custom_id,
--     not ctx.data.custom_id), since Discord always nests them there and
--     never sends them on the interaction's own top level.
--
--   ComponentContext:respond(content, opts) -> Response
--     Sends a new message in response to the interaction (type 4).
--
--   ComponentContext:update(content, opts) -> Response
--     Edits the message the component is attached to (type 7,
--     UPDATE_MESSAGE), mirrors pycord's ctx.response.edit_message.
--
--   ComponentContext:defer(opts) -> Response
--     Acknowledges the interaction without a visible response yet
--     (type 6, DEFERRED_UPDATE_MESSAGE unless opts.with_message is set,
--     which uses type 5, DEFERRED_CHANNEL_MESSAGE_WITH_SOURCE).

local class = require("../core/class")
local bitwise = require("../core/bitwise")

local ComponentContext = class("ComponentContext")

local function collect_component_values(components, into)
    for _, comp in ipairs(components or {}) do
        if comp.custom_id then
            if comp.value ~= nil then
                into[comp.custom_id] = comp.value
            elseif comp.values ~= nil then
                into[comp.custom_id] = comp.values
            elseif comp.checked ~= nil then
                into[comp.custom_id] = comp.checked
            end
        end
        if comp.component then
            collect_component_values({ comp.component }, into)
        end
        if comp.components then
            collect_component_values(comp.components, into)
        end
    end
end

function ComponentContext.new(interaction, client)
    local self = {}
    for key, value in pairs(interaction) do
        self[key] = value
    end
    setmetatable(self, { __index = ComponentContext })

    self.bot = client
    self.interaction_id = interaction.id
    self.interaction_token = interaction.token

    -- Discord nests custom_id and component_type inside interaction.data,
    -- never on the interaction's top level; hoist them here so callback
    -- code can read ctx.custom_id directly, matching the doc comment
    -- above and every example's usage.
    self.values_by_id = {}
    if interaction.data then
        self.custom_id = interaction.data.custom_id
        self.component_type = interaction.data.component_type
        self.values = interaction.data.values
        if interaction.data.components then
            collect_component_values(interaction.data.components, self.values_by_id)
        end
    end

    return self
end

local function build_message_data(content, opts)
    opts = opts or {}
    local data = { content = content }
    if opts.flags then
        data.flags = opts.flags
    end
    if opts.ephemeral then
        data.flags = bitwise.bor(data.flags or 0, 64)
    end
    if opts.embeds then
        data.embeds = opts.embeds
    end
    if opts.components then
        data.components = opts.components
    end
    if opts.files and #opts.files > 0 then
        local Multipart = require("../http/multipart")
        data = Multipart.with_attachments(data, opts.files)
    end
    return data
end

function ComponentContext:respond(content, opts)
    if not self.bot or not self.bot.rest then
        error("ComponentContext has no rest client attached, cannot respond", 0)
    end

    opts = opts or {}
    local payload = {
        type = 4, -- CHANNEL_MESSAGE_WITH_SOURCE
        data = build_message_data(content, opts),
    }

    return self.bot.rest:create_interaction_response(
        self.interaction_id,
        self.interaction_token,
        payload,
        opts.files
    )
end

function ComponentContext:update(content, opts)
    if not self.bot or not self.bot.rest then
        error("ComponentContext has no rest client attached, cannot update", 0)
    end

    opts = opts or {}
    local payload = {
        type = 7, -- UPDATE_MESSAGE
        data = build_message_data(content, opts),
    }

    return self.bot.rest:create_interaction_response(
        self.interaction_id,
        self.interaction_token,
        payload,
        opts.files
    )
end

function ComponentContext:defer(opts)
    opts = opts or {}
    if not self.bot or not self.bot.rest then
        error("ComponentContext has no rest client attached, cannot defer", 0)
    end

    local response_type = 6 -- DEFERRED_UPDATE_MESSAGE
    local data
    if opts.with_message then
        response_type = 5 -- DEFERRED_CHANNEL_MESSAGE_WITH_SOURCE
        if opts.ephemeral then
            data = { flags = 64 }
        end
    end

    return self.bot.rest:create_interaction_response(
        self.interaction_id,
        self.interaction_token,
        { type = response_type, data = data }
    )
end

function ComponentContext:edit(content, opts)
    if not self.bot or not self.bot.rest then
        error("ComponentContext has no rest client attached, cannot edit", 0)
    end
    opts = opts or {}
    local payload = build_message_data(content, opts)
    return self.bot.rest:edit_interaction_response(
        self.bot.application_id,
        self.interaction_token,
        payload,
        opts.files
    )
end

function ComponentContext:send_followup(content, opts)
    if not self.bot or not self.bot.rest then
        error("ComponentContext has no rest client attached, cannot send followup", 0)
    end
    opts = opts or {}
    local payload = build_message_data(content, opts)
    return self.bot.rest:create_followup_message(
        self.bot.application_id,
        self.interaction_token,
        payload,
        opts.files
    )
end

function ComponentContext:send_modal(modal)
    if not self.bot or not self.bot.rest then
        error("ComponentContext has no rest client attached, cannot send modal", 0)
    end
    local data = modal.to_component and modal:to_component() or modal
    return self.bot.rest:create_interaction_response(
        self.interaction_id,
        self.interaction_token,
        { type = 9, data = data }
    )
end

return ComponentContext
