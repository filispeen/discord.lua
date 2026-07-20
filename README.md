![Logo](md/wd.svg)

<div align="center">Discord.lua is a modern, easy to use, feature-rich, and async ready API wrapper for Discord written in Lua for the Luvit runtime.</div>

---

<div align="center">

![Lit](https://img.shields.io/badge/lit-324FFF?style=for-the-badge&logo=lit&logoColor=white)
![Lua](https://img.shields.io/badge/Lua-%232C2D72.svg?style=for-the-badge&logo=lit&logoColor=white)
[![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/filispeen/discord.lua/lit-publish.yml?branch=master&style=for-the-badge&logo=LIT&label=Publish%20to%20lit)](https://github.com/filispeen/discord.lua/actions/workflows/lit-publish.yml)


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

See more examples in <a href="/tree/master/examples/">`examples/`</a> directory:
- <a href="/blob/master/examples/basic_bot.lua">`basic_bot.lua`</a> - Basic bot with some functions
- <a href="/blob/master/examples/on_message.lua">`on_message.lua`</a> - Bot with on_message event
- <a href="/blob/master/examples/interaction_bot.lua">`interaction_bot.lua`</a> - Bot with interactions
- <a href="/blob/master/examples/view_button.lua">`view_button.lua`</a> - Button with View timeout
- <a href="/blob/master/examples/hybrid_command.lua">`hybrid_command.lua`</a> - Hybrid command (prefix + slash)
- <a href="/blob/master/examples/voice_play.lua">`voice_play.lua`</a> - Voice client usage
- <a href="/blob/master/examples/sharded_bot.lua">`sharded_bot.lua`</a> - Sharded bot with auto-sharding

## Reference
- <a href="https://github.com/Pycord-Development/pycord/">pycord</a>

## License

MIT License