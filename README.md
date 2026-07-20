![Logo](md/wd.svg)

<div align="center">Discord.lua is a modern, easy to use, feature-rich, and async ready API wrapper for Discord written in Lua for the Luvit runtime.</div>

---

<div align="center">
<div align="center" style="width: 70%;">

![Lit](https://img.shields.io/badge/lit-324FFF?style=for-the-badge&logo=lit&logoColor=white)
![Lua](https://img.shields.io/badge/Lua-%232C2D72.svg?style=for-the-badge&logo=lit&logoColor=white)
<br>
---

![Lint](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/filispeen/b673d810ff3949b6298d705c5fad191a/raw/lint-badge.json&style=for-the-badge)
![Tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/filispeen/b673d810ff3949b6298d705c5fad191a/raw/test-badge.json&style=for-the-badge)
![Rockspec](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/filispeen/b673d810ff3949b6298d705c5fad191a/raw/rockspec-badge.json&style=for-the-badge)
<br>
---

![Rockspec](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/filispeen/b673d810ff3949b6298d705c5fad191a/raw/lit-badge.json&style=for-the-badge)
</div>
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
local discord = require("discord.lua")

local bot = discord.Bot()

bot:on("ready", function()
    print("Bot is ready!")
end)

bot:command("ping", function(ctx)
    ctx:reply("Pong!")
end)

bot:run("YOUR_TOKEN")
```
Interactions bot
```lua
local discord = require("discord.lua")

local bot = discord.Bot()

bot:on("ready", function()
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

bot:run("YOUR_TOKEN")
```


## Full Examples

See more examples in <a href="/examples/">`examples/`</a> directory:
- <a href="/examples/basic_bot.lua">`basic_bot.lua`</a> - Basic bot with some functions
- <a href="/examples/on_message.lua">`on_message.lua`</a> - Bot with on_message event
- <a href="/examples/interaction_bot.lua">`interaction_bot.lua`</a> - Bot with interactions
- <a href="/examples/view_button.lua">`view_button.lua`</a> - Button with View timeout
- <a href="/examples/hybrid_command.lua">`hybrid_command.lua`</a> - Hybrid command (prefix + slash)
- <a href="/examples/voice_play.lua">`voice_play.lua`</a> - Voice client usage
- <a href="/examples/sharded_bot.lua">`sharded_bot.lua`</a> - Sharded bot with auto-sharding

## Reference
- <a href="https://github.com/Pycord-Development/pycord/">pycord</a>