![Logo](md/wd.svg)

<div align="center">Discord.lua is an asynchronous Discord API wrapper written in Lua for the Luvit runtime.</div>

---

<div align="center">
<div align="center" style="width: 70%;">

![Lit](https://img.shields.io/badge/lit-324FFF?style=for-the-badge&logo=lit&logoColor=white)
![Lua](https://img.shields.io/badge/Lua-%232C2D72.svg?style=for-the-badge&logo=lit&logoColor=white)
<br>
---

![Lint](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/filispeen/b673d810ff3949b6298d705c5fad191a/raw/lint-badge.json&style=for-the-badge)
![Tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/filispeen/b673d810ff3949b6298d705c5fad191a/raw/test-badge.json&style=for-the-badge)
<br>
</div>
</div>

---

## Features

- Coroutine-based async I/O on Luvit
- Per-route and global rate limit handling
- Optimized for speed and low memory usage
- Full Discord application API support

## Installation

### Luvit
```bash
lit install filispeen/discord.lua
```

On the first `require("discord.lua")`, Linux x64 and Windows x64 installations download the native voice bundle automatically. See the [installation guide](docs/getting-started/installation.md) for platform requirements.

## Quick example

### Traditional bot
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

### Interactions bot
```lua
local discord = require("discord.lua")

local bot = discord.Bot()

bot:on("ready", function()
    print("Bot is ready!")
end)

bot:slash_command("ping", {
    description = "Repeats back pong",
    callback = function(ctx)
        ctx:respond("Pong!")
    end,
})

bot:slash_command("roll", {
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

## Full examples

More examples are in the <a href="/examples/">`examples/`</a> directory:
- <a href="/examples/basic_bot.lua">`basic_bot.lua`</a> - Minimal bot with a `ping` prefix command
- <a href="/examples/on_message.lua">`on_message.lua`</a> - Bot listening to the `on_message` event
- <a href="/examples/interaction_bot.lua">`interaction_bot.lua`</a> - Bot with slash commands and interactions
- <a href="/examples/view_button.lua">`view_button.lua`</a> - Button with a `View` timeout
- <a href="/examples/hybrid_command.lua">`hybrid_command.lua`</a> - Hybrid command (prefix and slash)
- <a href="/examples/voice_play.lua">`voice_play.lua`</a> - Playing audio with the voice client
- <a href="/examples/sharded_bot.lua">`sharded_bot.lua`</a> - Auto-sharded gateway setup

## Feature comparison

✅ Built in · ⚠️ Manual or limited support · ❌ No built-in high-level API
<div align="center">

| Feature                              | discord.lua | Discordia |
| ------------------------------------ | :---------: | :-------: |
| Gateway events                       |      ✅      |     ✅     |
| REST API and Discord models          |      ✅      |     ✅     |
| Cache-backed models                  |      ✅      |     ✅     |
| Rate-limit handling                  |      ✅      |     ✅     |
| Prefix command framework             |      ✅      | ⚠️ Manual |
| Slash commands                       |      ✅      |     ❌     |
| User and message context commands    |      ✅      |     ❌     |
| Command groups and subcommands       |      ✅      |     ❌     |
| Autocomplete                         |      ✅      |     ❌     |
| Application command sync             |      ✅      |     ❌     |
| Hybrid prefix + slash commands       |      ✅      |     ❌     |
| Interaction responses and follow-ups |      ✅      |     ❌     |
| Buttons and select menus             |      ✅      |     ❌     |
| Views and timeouts                   |      ✅      |     ❌     |
| Modals                               |      ✅      |     ❌     |
| Discord Components V2                |      ✅      |     ❌     |
| Scheduled events                     |      ✅      |     ❌     |
| AutoMod                              |      ✅      |     ❌     |
| Polls                                |      ✅      |     ❌     |
| Monetization                         |      ✅      |     ❌     |
| Application emojis                   |      ✅      |     ❌     |
| Checks, cooldowns and error handlers |      ✅      |     ❌     |
| Extensions, cogs and task helpers    |      ✅      |     ❌     |
| Voice                                |      ✅      |     ✅     |
| Automatic gateway sharding           |      ✅      |     ✅     |
</div>

## Star history

[![Star History Chart](https://api.star-history.com/chart?repos=filispeen/discord.lua&type=date&legend=top-left)](https://www.star-history.com/?repos=filispeen%2Fdiscord.lua&type=date&releases=&legend=top-left)

## Reference
- <a href="https://github.com/Pycord-Development/pycord/">pycord</a>
