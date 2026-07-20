-- examples/on_message.lua
-- Example: Listening to raw messages with on_message.
--
-- bot:on_message(callback) is sugar for bot:on("message_create", callback)
-- and fires for every message the gateway sees, including ones that also
-- match a prefix command below. Use it for logging, auto-moderation, or
-- reacting to messages that are not commands at all.

local discord = require("discord.lua")

-- Reading message.content needs GUILD_MESSAGES to see the message and
-- MESSAGE_CONTENT (privileged, enable it on the dev portal too).
local intents = discord.enums.combine_intents(
    discord.enums.INTENTS.GUILDS,
    discord.enums.INTENTS.GUILD_MESSAGES,
    discord.enums.INTENTS.MESSAGE_CONTENT
)

local bot = discord.Bot(nil, intents)

bot:on("ready", function()
    print("Bot is ready!")
end)

-- Fires for every message, prefix commands included.
bot:on_message(function(message)
    if message.author and message.author.bot then
        return
    end
    print(message.author and message.author.username or "unknown", "said:", message.content)
end)

-- Simple keyword auto-reply, separate from the command system below.
bot:on_message(function(message)
    if message.content == "hello" then
        message:reply("Hey there!")
    end
end)

bot:register_command("ping", function(message)
    message:reply("Pong!")
end, "!", "Replies with pong")

bot:run("YOUR_BOT_TOKEN")