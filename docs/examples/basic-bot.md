# Basic bot

This prefix bot uses the package-call constructor so the intent bitfield reaches the correct parameter.

```lua
local discord = require("discord.lua")

local intents = discord.enums.combine_intents(
    discord.enums.INTENTS.GUILDS,
    discord.enums.INTENTS.GUILD_MESSAGES,
    discord.enums.INTENTS.MESSAGE_CONTENT
)

local bot = discord(nil, intents)

bot:on("ready", function()
    print("Logged in as " .. bot.user.username)
end)

bot:command("ping", function(message)
    message:reply("Pong!")
end, "Reply with Pong!")

bot:on("command_error", function(message, err)
    print("Command error:", tostring(err))
    message:reply("Something went wrong.")
end)

bot:run(assert(os.getenv("DISCORD_TOKEN"), "DISCORD_TOKEN is required"))
```
