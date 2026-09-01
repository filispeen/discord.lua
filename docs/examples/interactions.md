# Interactions

This component example uses the explicit lifecycle required by the current Bot implementation.

```lua
local discord = require("discord.lua")
local View = require("discord.lua/lib/ui/view")
local Button = require("discord.lua/lib/ui/button")

local token = assert(os.getenv("DISCORD_TOKEN"), "DISCORD_TOKEN is required")
local bot = discord.Bot.new(token, nil, discord.enums.INTENTS.GUILDS)

bot:connect()

local view = View.new({ timeout = 60000 })
view:add(Button.new({
    custom_id = "counter_increment",
    label = "Increment",
    style = "primary",
}))

local count = 0
bot:interaction("counter_increment", function(ctx)
    count = count + 1
    ctx:update("Count: " .. count, { components = view:to_components() })
end)
bot:component(view)

bot:slash_command("counter", {
    description = "Show a counter button",
    callback = function(ctx)
        ctx:respond("Count: 0", { components = view:to_components() })
    end,
})

bot:on("application_command_error", function(ctx, err)
    print("Interaction error:", tostring(err))
    ctx:respond("Could not process the interaction.", { ephemeral = true })
end)

bot.client:start_gateway()
```

Do not replace `connect()`/`client:start_gateway()` with `run()` in this example: `run()` reconnects and clears the registered component handlers.
