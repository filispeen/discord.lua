-- examples/hybrid_command.lua
-- Example: Hybrid command (prefix + slash).
--
-- A hybrid command allows the same logic to be triggered via:
--   - Prefix: !ping
--   - Slash: /ping
--
-- This reduces code duplication and keeps logic in one place. There is
-- no single "hybrid" registration helper, so the same handler is passed
-- to both register_command and register_application_command.

local discord = require("discord.lua")

-- Prefix command below needs GUILD_MESSAGES to see the message and
-- MESSAGE_CONTENT (privileged, enable it on the dev portal too) to read
-- message.content. Slash commands alone would only need GUILDS.
local intents = discord.enums.combine_intents(
    discord.enums.INTENTS.GUILDS,
    discord.enums.INTENTS.GUILD_MESSAGES,
    discord.enums.INTENTS.MESSAGE_CONTENT
)

local bot = discord.Bot(nil, intents)

bot:on("ready", function()
    print("Bot is ready!")
end)

local function ping(ctx)
    ctx:reply("Pong!")
end

bot:register_command("ping", ping, "!", "Replies with pong")
bot:register_application_command("ping", {
    description = "Replies with pong",
    callback = ping,
})

-- A slash-only command with an option.
-- ctx.args.user holds the parsed User option.
bot:register_application_command("greet", {
    description = "Greet someone",
    options = {
        {
            name = "user",
            type = Bot.enums.OPTION_TYPE.USER,
            description = "The user to greet",
            required = true,
        },
    },
    callback = function(ctx)
        local user = ctx:require_arg("user")
        ctx:respond("Hello, <@" .. user.id .. ">!")
    end,
})

bot:run("YOUR_BOT_TOKEN")