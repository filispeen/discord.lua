-- examples/basic_bot.lua
-- Example: Basic bot skeleton.
--
-- The smallest useful bot: connect, log when ready, reply to one prefix
-- command. Good starting point to copy for a new bot before adding
-- slash commands, buttons, or voice.

local discord = require("discord.lua")

-- The ping command below is a prefix command, so it needs GUILD_MESSAGES
-- to see the message and MESSAGE_CONTENT (privileged, enable it on the
-- dev portal too) to read the text. default_intents() alone is not
-- enough since MESSAGE_CONTENT is privileged and excluded from it.
local intents = discord.enums.combine_intents(
    discord.enums.INTENTS.GUILDS,
    discord.enums.INTENTS.GUILD_MESSAGES,
    discord.enums.INTENTS.MESSAGE_CONTENT
)

local bot = discord.Bot(nil, intents)

bot:on("ready", function()
    print("Bot is ready!")
    if bot.user then
        print("Logged in as " .. bot.user.username)
    end
end)

bot:register_command("ping", function(ctx)
    ctx:reply("Pong!")
end, "!", "Replies with pong")

bot:run("YOUR_BOT_TOKEN")