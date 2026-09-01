# Commands

This example combines a slash command and a bridge command. Enable Message Content only because the bridge command also has a prefix form.

```lua
local discord = require("discord.lua")
local OPTION = discord.enums.OPTION_TYPE

local intents = discord.enums.combine_intents(
    discord.enums.INTENTS.GUILDS,
    discord.enums.INTENTS.GUILD_MESSAGES,
    discord.enums.INTENTS.MESSAGE_CONTENT
)
local bot = discord(nil, intents)

bot:slash_command("roll", {
    description = "Roll a die",
    options = {
        {
            name = "sides",
            description = "Number of sides",
            type = OPTION.INTEGER,
            required = false,
        },
    },
    callback = function(ctx)
        local sides = ctx:get_arg("sides", 6)
        ctx:respond("Rolled " .. math.random(1, sides))
    end,
})

bot:bridge_command("ping", {
    description = "Reply with Pong!",
    callback = function(ctx)
        ctx:respond("Pong!")
    end,
})

bot:on("application_command_error", function(ctx, err)
    print("Application command error:", tostring(err))
    ctx:respond("Command failed.", { ephemeral = true })
end)

bot:run(assert(os.getenv("DISCORD_TOKEN"), "DISCORD_TOKEN is required"))
```

Use `/roll` or `/ping`; the bridge command also responds to `!ping`.
