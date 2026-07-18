-- lib/interactions/slash.lua
-- Slash command context for application commands
--
-- Public Contract:
--   SlashCommandContext.new(interaction, client) -> SlashCommandContext
--
--   SlashCommandContext:author -> User
--     Interaction author.
--
--   SlashCommandContext:guild -> Guild or nil
--     Guild (nil for DMs).
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
function M.new(interaction, client)
    local ctx = {
        author = interaction.user,
        guild = interaction.guild,
        channel = interaction.channel,
        message = interaction.message,
        args = {},
        options = {},
        bot = client,
        interaction_id = interaction.id,
        interaction_token = interaction.token,
    }
    setmetatable(ctx, {
        __index = M.SlashCommandContext
    })

    -- Parse arguments from interaction data
    if interaction.data and interaction.data.options then
        for _, opt in ipairs(interaction.data.options) do
            ctx:parse_option(opt)
        end
    end

    return ctx
end

-- Parse an option
function M.SlashCommandContext:parse_option(opt)
    local name = opt.name

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
        -- User option
        self.args[name] = {
            id = opt.user.id,
            discriminator = opt.user.discriminator,
            username = opt.user.username,
            global_name = opt.user.global_name,
        }
    elseif opt.type == 7 then
        -- Channel option
        self.args[name] = {
            id = opt.channel.id,
            type = opt.channel.type,
            name = opt.channel.name,
        }
    elseif opt.type == 8 then
        -- Role option
        self.args[name] = {
            id = opt.role.id,
            name = opt.role.name,
        }
    elseif opt.type == 10 then
        -- Mentionable option
        self.args[name] = {
            id = opt.mentionable.id,
            type = opt.mentionable.type,
            name = opt.mentionable.name,
        }
    elseif opt.type == 1 then
        -- Subcommand
        if opt.options then
            for _, sub in ipairs(opt.options) do
                self:parse_option(sub)
            end
        end
    elseif opt.type == 2 then
        -- Subcommand group
        if opt.options then
            for _, sub in ipairs(opt.options) do
                self:parse_option(sub)
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
