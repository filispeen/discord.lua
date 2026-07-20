![Logo](md/wd.svg)

<div align="center">Discord.lua is a modern, easy to use, feature-rich, and async ready API wrapper for Discord written in Lua for the Luvit runtime.</div>

---

<div align="center">
[![Publish to Lit](https://github.com/filispeen/discord.lua/actions/workflows/lit-publish.yml/badge.svg)](https://github.com/filispeen/discord.lua/actions/workflows/lit-publish.yml)
</div>

---

## Key Features
- Asynchronous
- Proper rate limit handling.
- Optimised for both speed and memory usage.
- Full application API support.


## Installation
### luvit
```bash
lit install filispeen/discord.lua
```
<!--
### luarocks
```bash
luarocks install discord.lua
```-->

## Quick example
Traditional bot
```lua
local Bot = require("discord.lua")

local client = Bot()

client:on("ready", function()
    print("Bot is ready!")
end)

client:command("ping", function(msg)
    msg:reply("Pong!")
end)

client:run("YOUR_TOKEN")
```
Interactions bot
```lua
local Bot = require("discord.lua")

local client = Bot()

client:on("ready", function()
    print("Bot is ready!")
end)

bot:register_application_command("ping", {
    description = "Repeats back pong",
    callback = function(ctx)
        ctx:respond("Pong!")
    end,
})

bot:register_application_command("roll", {
    description = "Rolls a die",
    options = {
        {
            name = "sides",
            type = enums.OPTION_TYPE.INTEGER,
            description = "Number of sides, defaults to 6",
            required = false,
        },
    },
    callback = function(ctx)
        local sides = ctx:get_arg("sides", 6)
        ctx:respond("Rolled: " .. math.random(1, sides))
    end,
})

client:run("YOUR_TOKEN")
```


## Full Examples

See more examples in <a href="/tree/main/examples/">`examples/`</a> directory:
- <a href="/blob/main/examples/basic_bot.lua">`basic_bot.lua`</a> - Basic bot with some functions
- <a href="/blob/main/examples/on_message.lua">`on_message.lua`</a> - Bot with on_message event
- <a href="/blob/main/examples/interaction_bot.lua">`interaction_bot.lua`</a> - Bot with interactions
- <a href="/blob/main/examples/view_button.lua">`view_button.lua`</a> - Button with View timeout
- <a href="/blob/main/examples/hybrid_command.lua">`hybrid_command.lua`</a> - Hybrid command (prefix + slash)
- <a href="/blob/main/examples/voice_play.lua">`voice_play.lua`</a> - Voice client usage
- <a href="/blob/main/examples/sharded_bot.lua">`sharded_bot.lua`</a> - Sharded bot with auto-sharding

## Reference
- <a href="https://github.com/Pycord-Development/pycord/">pycord</a>

## License

MIT License