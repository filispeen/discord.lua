# discord.lua

An independent Lua port of [pycord](https://github.com/Pycord-Development/pycord), a fork of [discord.py](https://github.com/Rapptz/discord.py).

[![LuaRocks](https://img.shields.io/luarocks/v/discord.lua)](https://luarocks.org/modules/discord.lua)
[![LuaRocks](https://img.shields.io/luarocks/v/discord.lua)](https://luarocks.org/modules/discord.lua)

## Features

- **Full REST API**: All Discord REST endpoints
- **Gateway Bot**: WebSocket connection with heartbeats, resume, and sharding
- **Caching**: LRU cache with configurable policies
- **Prefix Commands**: `ext.commands` style with Cogs, Groups, Converters, Checks
- **Application Commands**: Slash commands, context menus, autocomplete
- **UI Components**: Buttons, Select Menus, Modals with Views
- **Voice**: Voice channels, Opus encoding, UDP streaming

## Installation

```bash
luarocks install discord.lua
```

## Quick Start

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

## Modules

### Core

- `core.class` - Class system
- `core.emitter` - Event emitter
- `core.enums` - Enum constants
- `core.errors` - Error classes

### HTTP

- `http.client` - HTTP client with rate limiting
- `http.ratelimiter` - Rate limit bucket manager

### Gateway

- `gateway.shard` - Single shard WebSocket connection
- `gateway.manager` - Shard manager with auto-sharding
- `gateway.opcodes` - Gateway opcodes

### Models

- `models.client` - Bot client
- `models.guild` - Guild model
- `models.channel` - Channel model
- `models.message` - Message model
- `models.user` - User model
- `models.member` - Member model
- `models.role` - Role model
- `models.embed` - Embed builder
- `models.emoji` - Emoji model
- `models.webhook` - Webhook model
- `models.permission` - Permission bitmath

### Commands

- `commands.bot` - Bot class with prefix commands
- `commands.cog` - Cog class
- `commands.command` - Command class
- `commands.group` - Group class
- `commands.converters` - Type converters
- `commands.checks` - Command checks

### Interactions

- `interactions.application_command` - Application command
- `interactions.slash` - Slash command context
- `interactions.context_menu` - Context menu commands
- `interactions.hybrid` - Hybrid commands

### UI

- `ui.view` - View class
- `ui.button` - Button component
- `ui.select` - SelectMenu component
- `ui.modal` - Modal component

### Cache

- `cache.store` - Cache store
- `cache.policy` - Cache policies

### Voice

- `voice.voice_client` - Voice client
- `voice.voice_gateway` - Voice gateway
- `voice.udp` - UDP handling
- `voice.opus` - Opus encoder/decoder

## Examples

### Basic Bot

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

### Cog System

```lua
local Bot = require("discord.lua")
local client = Bot()

local MyCog = require("commands.cog")
local MyCommand = require("commands.command")

local MyCommandInstance = MyCommand.new({
    name = "hello",
    description = "Say hello!",
})

MyCommandInstance.callback = function(msg, args)
    msg:reply("Hello, " .. args[1] or "there!")
end

local MyCogInstance = MyCog.new()
MyCogInstance.commands = { MyCommandInstance }

client:add_cog(MyCogInstance)
client:run("YOUR_TOKEN")
```

### UI Components

```lua
local Bot = require("discord.lua")
local client = Bot()

local view = require("ui.view")
local button = require("ui.button")

local completed = false

local my_view = view:new()
my_view:add(button:new({
    label = "Click me",
    style = "primary",
    custom_id = "my_button",
    disabled = false,
}))

my_view:timeout(30000)

client:interaction("my_button", function(interaction)
    interaction:respond({
        type = "channel_message_with_source",
        content = "Button clicked!",
    })
    completed = true
    my_view:remove()
end)

client:component(my_view)
client:run("YOUR_TOKEN")
```

### Voice

```lua
local Bot = require("discord.lua")
local client = Bot()

client:on("voice_state_update", function(before, after)
    if after.channel_id and after.member and not before.channel_id then
        local voice_client = client.voice_client(after.member.user.id, after.channel_id)
        voice_client:connect()
        voice_client:play(some_source)
    end
end)

client:run("YOUR_TOKEN")
```

### Sharding

```lua
local Bot = require("discord.lua")

local client = Bot()

client.on_ready(function()
    -- Shard manager handles auto-sharding automatically
    -- Just listen for shard ready events
    client.on_shard_ready(function(shard_id)
        print("Shard " .. shard_id .. " is ready")
    end)
end)

client:run("YOUR_TOKEN")
```

## Examples

See the `examples/` directory for more examples:
- `view_button.lua` - Button with View timeout
- `hybrid_command.lua` - Hybrid command (prefix + slash)
- `voice_play.lua` - Voice client usage
- `sharded_bot.lua` - Sharded bot with auto-sharding

## 1.0 Release Checklist

- [x] M1-M6 tests passing
- [x] M7 voice code implemented
- [x] M7 voice tests added
- [x] Auto-sharding implemented (M8)
- [x] luacheck clean (excluding pre-existing warnings)
- [x] luadoc-ready documentation
- [x] Examples directory with working examples
- [x] README.md documentation
- [x] CI/CD matrix configured

## License

MIT License