-- lib/interactions/autocomplete_context.lua
-- Autocomplete context, contract mirrors pycord discord.AutocompleteContext.
--
-- Public Contract:
--   AutocompleteContext.new(interaction, client, focused_name) -> ctx
--     interaction: raw APPLICATION_COMMAND_AUTOCOMPLETE interaction payload
--     client: Client instance (available as ctx.bot / ctx.interaction.client)
--     focused_name: string, the name of the option currently being typed
--
--   ctx.value -> string or number or nil
--     The partial value currently typed into the focused option.
--
--   ctx.options -> table
--     name -> value for every option already provided in this interaction,
--     including the focused one, so a later option's autocomplete callback
--     can branch on an earlier option's choice (see pycord's
--     ac_example / get_animals pattern keyed off ctx.options["color"]).
--
--   ctx.command -> ApplicationCommand or nil
--     The command this autocomplete interaction belongs to, if resolvable.
--
--   ctx.interaction -> table
--     The raw interaction payload.
--
--   ctx.bot -> Client
--     The client instance, mirrors pycord's ctx.interaction.client shortcut.

local class = require("core.class")

local AutocompleteContext = class("AutocompleteContext")

-- Flattens interaction.data.options into a plain name -> value table,
-- recursing into subcommand/subcommand group option nodes (types 1 and 2)
-- the same way SlashCommandContext:parse_option does.
local function flatten_options(options, into)
    for _, opt in ipairs(options or {}) do
        if opt.type == 1 or opt.type == 2 then
            if opt.options then
                flatten_options(opt.options, into)
            end
        else
            into[opt.name] = opt.value
        end
    end
    return into
end

function AutocompleteContext.new(interaction, client, focused_name, command)
    local self = setmetatable({}, AutocompleteContext)

    self.interaction = interaction
    self.bot = client
    self.command = command

    local data = interaction and interaction.data or {}
    self.options = flatten_options(data.options, {})
    self.value = self.options[focused_name]

    return self
end

return AutocompleteContext
