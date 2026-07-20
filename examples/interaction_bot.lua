-- examples/interaction_bot.lua
-- Example: Bot built entirely on slash commands.
--
-- No prefix commands here, just register_application_command with typed
-- options. ctx:respond/reply must be called within Discord's 3 second
-- interaction window; ctx:edit can update the response afterward.

local discord = require("discord.lua")

-- Interactions arrive over the same gateway connection, but reading them
-- does not need a privileged intent. GUILDS is enough to cache the guild
-- the interaction came from.
local bot = discord.Bot(nil, discord.enums.INTENTS.GUILDS)

bot:on("ready", function()
    print("Bot is ready!")
end)

bot:register_application_command("echo", {
    description = "Repeats back what you typed",
    options = {
        {
            name = "text",
            type = discord.enums.OPTION_TYPE.STRING,
            description = "Text to repeat",
            required = true,
        },
    },
    callback = function(ctx)
        local text = ctx:require_arg("text")
        ctx:respond(text)
    end,
})

bot:register_application_command("roll", {
    description = "Rolls a die",
    options = {
        {
            name = "sides",
            type = discord.enums.OPTION_TYPE.INTEGER,
            description = "Number of sides, defaults to 6",
            required = false,
        },
    },
    callback = function(ctx)
        local sides = ctx:get_arg("sides", 6)
        ctx:respond("Rolled: " .. math.random(1, sides))
    end,
})

bot:register_application_command("note", {
    description = "Sends a private note only you can see",
    options = {
        {
            name = "message",
            type = discord.enums.OPTION_TYPE.STRING,
            description = "The note content",
            required = true,
        },
    },
    callback = function(ctx)
        local message = ctx:require_arg("message")
        ctx:respond("Noted: " .. message, { ephemeral = true })
    end,
})

bot:run("YOUR_BOT_TOKEN")