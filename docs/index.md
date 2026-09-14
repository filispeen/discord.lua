# discord.lua — Discord bot library for Lua and Luvit

`discord.lua` is a Discord bot library and Discord API wrapper for Lua on the Luvit runtime. It provides a single package for building bots around Discord gateway events, REST-backed models, prefix and slash commands, interactions, UI components, voice, and sharding.

The library is aimed at Lua developers who want a practical Discord client without leaving the Luvit ecosystem. It includes higher-level helpers for common bot features while still exposing the underlying Discord concepts through documented models and APIs.

## Install

Install the package with Lit:

```sh
lit install filispeen/discord.lua
```

Then load it with:

```lua
local discord = require("discord.lua")
```

See the full [installation guide](getting-started/installation.md) for runtime and voice dependency details.

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

## What discord.lua covers

- Discord Gateway events plus cache-backed messages, channels, members, roles, and voice states.
- Prefix commands, slash commands, command groups, context menus, autocomplete, and hybrid command flows.
- Interaction responses, follow-ups, buttons, selects, views, modals, and Discord Components v2 items.
- Embeds, file uploads, REST-backed models, voice playback and recording, and automatic gateway sharding.
- Extension, cog, task, check, cooldown, and error-handling helpers for larger bots.

## Start building

If this is your first project, follow [Build your first bot](getting-started/first-bot.md). For application commands, go directly to the [slash commands guide](guides/slash-commands.md). Voice bots are covered in the [Discord voice guide](guides/voice.md), while lower-level types and methods are documented in the [API reference](api/bot.md).

You can also browse the practical [guides](guides/events.md) and complete [examples](examples/basic-bot.md) to see how the library fits together.
