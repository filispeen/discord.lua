-- lib/interactions/slash.lua
-- Slash command context for application commands
--
-- Public Contract:
--   SlashCommandContext.new(interaction, client, context_class) -> SlashCommandContext
--     context_class: optional table to use as the context's metatable
--     __index instead of M.SlashCommandContext, for custom context
--     subclasses (see Bot:get_application_context). Should set its own
--     __index chain back to M.SlashCommandContext (or a compatible table)
--     to keep the built-in methods (respond/edit/parse_option/etc)
--     available, the same way pycord's ApplicationContext subclasses do
--     via normal Python inheritance.
--
--   SlashCommandContext:author -> User
--     Interaction author. Built from interaction.member.user for guild
--     interactions, interaction.user for DMs (Discord only ever sends one
--     of the two).
--
--   SlashCommandContext:guild -> table or nil
--     Minimal { id = ... } table built from interaction.guild_id, since
--     Discord's interaction payload never includes a full guild object.
--     nil for DMs.
--
--   SlashCommandContext:channel -> Channel
--     Channel.
--
--   SlashCommandContext:message -> Message or nil
--     Message (nil for slash commands).
--
--   SlashCommandContext:args -> table
--     Parsed command arguments.
--
--   SlashCommandContext:options -> table
--     Command options (choices, autocomplete results).
--
--   SlashCommandContext:bot -> Client
--     Client instance.
--
--   SlashCommandContext:reply(message, options) -> Response
--     Reply to the interaction.

local M = {}

-- SlashCommandContext class
M.SlashCommandContext = {
    author = nil,
    guild = nil,
    channel = nil,
    message = nil,
    args = {},
    options = {},
    bot = nil,
}

-- Create a new context
function M.new(interaction, client, context_class)
    -- Discord only ever sends one of interaction.user or
    -- interaction.member.user, never both: interaction.user is set for
    -- DM interactions, interaction.member.user for guild interactions.
    -- Falling back to interaction.user alone left ctx.author nil for
    -- every real guild invocation.
    local author = interaction.user
    if not author and interaction.member then
        author = interaction.member.user
    end

    -- Discord's interaction payload does not include a full guild
    -- object, only interaction.guild_id (a snowflake string), so ctx.guild
    -- is built as a minimal { id = ... } table rather than left as the
    -- always-nil interaction.guild field. nil for DMs, matching the
    -- documented "Guild or nil" contract.
    local guild = nil
    if interaction.guild_id then
        guild = { id = interaction.guild_id }
    end

    local ctx = {
        author = author,
        guild = guild,
        channel = interaction.channel,
        message = interaction.message,
        args = {},
        options = {},
        bot = client,
        interaction_id = interaction.id,
        interaction_token = interaction.token,
    }
    setmetatable(ctx, {
        __index = context_class or M.SlashCommandContext
    })

    -- Parse arguments from interaction data
    if interaction.data and interaction.data.options then
        for _, opt in ipairs(interaction.data.options) do
            ctx:parse_option(opt, interaction.data.resolved)
        end
    end

    -- Resolve a context menu command's target (user or message command),
    -- mirrors pycord passing member/message as the second callback argument.
    -- interaction.data.target_id points into interaction.data.resolved.
    local data = interaction.data
    if data and data.target_id and data.resolved then
        if data.resolved.members and data.resolved.members[data.target_id] then
            ctx.target_user = data.resolved.members[data.target_id]
        elseif data.resolved.users and data.resolved.users[data.target_id] then
            ctx.target_user = data.resolved.users[data.target_id]
        end

        if data.resolved.messages and data.resolved.messages[data.target_id] then
            ctx.target_message = data.resolved.messages[data.target_id]
        end
    end

    return ctx
end

-- Parse an option. resolved is interaction.data.resolved, needed to look
-- up the actual User/Channel/Role/Member objects for option types 6-8/10,
-- since Discord only sends their snowflake id as opt.value, never an
-- inline user/channel/role/mentionable field on the option itself.
function M.SlashCommandContext:parse_option(opt, resolved)
    local name = opt.name
    resolved = resolved or {}

    if opt.type == 3 then
        -- String option
        self.args[name] = opt.value
    elseif opt.type == 4 then
        -- Integer option
        self.args[name] = tonumber(opt.value)
    elseif opt.type == 5 then
        -- Boolean option
        self.args[name] = opt.value == true or opt.value == "true"
    elseif opt.type == 6 then
        -- User option: resolved via interaction.data.resolved.users,
        -- opt.value is just the user id.
        local user = resolved.users and resolved.users[opt.value]
        if user then
            self.args[name] = {
                id = user.id,
                discriminator = user.discriminator,
                username = user.username,
                global_name = user.global_name,
            }
        else
            self.args[name] = { id = opt.value }
        end
    elseif opt.type == 7 then
        -- Channel option: resolved via interaction.data.resolved.channels,
        -- opt.value is just the channel id.
        local channel = resolved.channels and resolved.channels[opt.value]
        if channel then
            self.args[name] = {
                id = channel.id,
                type = channel.type,
                name = channel.name,
            }
        else
            self.args[name] = { id = opt.value }
        end
    elseif opt.type == 8 then
        -- Role option: resolved via interaction.data.resolved.roles,
        -- opt.value is just the role id.
        local role = resolved.roles and resolved.roles[opt.value]
        if role then
            self.args[name] = {
                id = role.id,
                name = role.name,
            }
        else
            self.args[name] = { id = opt.value }
        end
    elseif opt.type == 10 then
        -- Mentionable option: opt.value can be a user id or a role id,
        -- check resolved.users first, then resolved.roles.
        local user = resolved.users and resolved.users[opt.value]
        local role = resolved.roles and resolved.roles[opt.value]
        if user then
            self.args[name] = {
                id = user.id,
                type = "user",
                name = user.global_name or user.username,
            }
        elseif role then
            self.args[name] = {
                id = role.id,
                type = "role",
                name = role.name,
            }
        else
            self.args[name] = { id = opt.value }
        end
    elseif opt.type == 1 then
        -- Subcommand
        if opt.options then
            for _, sub in ipairs(opt.options) do
                self:parse_option(sub, resolved)
            end
        end
    elseif opt.type == 2 then
        -- Subcommand group
        if opt.options then
            for _, sub in ipairs(opt.options) do
                self:parse_option(sub, resolved)
            end
        end
    end
end

-- Get an argument with default
function M.SlashCommandContext:get_arg(name, default)
    local value = self.args[name]
    if value then
        return value
    end
    return default
end

-- Get an argument or throw error
function M.SlashCommandContext:require_arg(name)
    if self.args[name] then
        return self.args[name]
    end
    error("Missing required argument: " .. name, 0)
end

-- Sends the initial response to this interaction, mirrors pycord's
-- ctx.respond(content, ephemeral=False). Must be called within Discord's
-- 3 second interaction window; after that use ctx:edit instead.
function M.SlashCommandContext:respond(content, opts)
    opts = opts or {}
    if not self.bot or not self.bot.rest then
        error("SlashCommandContext has no rest client attached, cannot respond", 0)
    end

    local data = { content = content }
    if opts.ephemeral then
        data.flags = 64
    end
    if opts.embeds then
        data.embeds = opts.embeds
    end
    if opts.components then
        data.components = opts.components
    end

    local payload = {
        type = 4, -- CHANNEL_MESSAGE_WITH_SOURCE
        data = data,
    }

    return self.bot.rest:create_interaction_response(
        self.interaction_id,
        self.interaction_token,
        payload
    )
end

-- Alias for respond, for familiarity with Message:reply.
function M.SlashCommandContext:reply(content, opts)
    return self:respond(content, opts)
end

-- Edits the original interaction response, mirrors pycord's ctx.edit.
function M.SlashCommandContext:edit(content, opts)
    opts = opts or {}
    if not self.bot or not self.bot.rest then
        error("SlashCommandContext has no rest client attached, cannot edit", 0)
    end

    local payload = { content = content }
    if opts.embeds then
        payload.embeds = opts.embeds
    end
    if opts.components then
        payload.components = opts.components
    end

    return self.bot.rest:edit_interaction_response(
        self.bot.application_id,
        self.interaction_token,
        payload
    )
end

return M
