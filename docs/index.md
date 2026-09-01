# discord.lua

`discord.lua` is a Discord bot library for Lua on the Luvit runtime.

## Install

```sh
lit install filispeen/discord.lua
```

## Minimal bot

```lua
local discord = require("discord.lua")

local bot = discord()

bot:on("ready", function()
    print("Ready as " .. bot.user.username)
end)

bot:command("ping", function(message)
    message:reply("Pong!")
end)

bot:run(assert(os.getenv("DISCORD_TOKEN"), "DISCORD_TOKEN is required"))
```

For a prefix bot, enable the Message Content intent in both your bot code and the Discord Developer Portal. See [Configuration](getting-started/configuration.md).

## Included APIs

- Gateway events and cache-backed messages, channels, members, roles, and voice states.
- Prefix commands, slash commands, command groups, context menus, autocomplete, and bridge commands.
- Interaction responses, follow-ups, components, views, modals, and Discord Components v2 items.
- Message embeds, files, REST-backed models, voice playback and recording, and automatic gateway sharding.

Read [Getting started](getting-started/installation.md), the practical [Guides](guides/events.md), or the [API reference](api/bot.md).
