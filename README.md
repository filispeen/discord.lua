# discord.lua

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
 
local bot = Bot(nil, Bot.enums.combine_intents(
    Bot.enums.INTENTS.GUILDS,
    Bot.enums.INTENTS.GUILD_MESSAGES,
    Bot.enums.INTENTS.MESSAGE_CONTENT
))
 
bot:on("ready", function()
    print("Bot is ready!")
    if bot.user then
        print("Logged in as " .. bot.user.username)
    end
end)
 
bot:register_command("ping", function(message)
    message:reply("Pong!")
end, "!", "Replies with pong")
 
bot:run("YOUR_TOKEN")
```
 
### Interaction Bot
 
```lua
local Bot = require("discord.lua")
 
-- Interactions arrive over the same gateway connection, but reading them
-- does not need a privileged intent. GUILDS is enough.
local bot = Bot(nil, Bot.enums.INTENTS.GUILDS)
 
bot:on("ready", function()
    print("Bot is ready!")
end)
 
bot:register_application_command("echo", {
    description = "Repeats back what you typed",
    options = {
        {
            name = "text",
            type = Bot.enums.OPTION_TYPE.STRING,
            description = "Text to repeat",
            required = true,
        },
    },
    callback = function(ctx)
        local text = ctx:require_arg("text")
        ctx:respond(text)
    end,
})
 
bot:run("YOUR_TOKEN")
```
 

## Examples

See more examples in <a href="/tree/main/examples/">`examples/`</a> directory:
- <a href="/blob/main/examples/basic_bot.lua">`basic_bot.lua`</a> - Basic bot with some functions
- <a href="/blob/main/examples/on_message.lua">`on_message.lua`</a> - Bot with on_message event
- <a href="/blob/main/examples/interaction_bot.lua">`interaction_bot.lua`</a> - Bot with interactions
- <a href="/blob/main/examples/view_button.lua">`view_button.lua`</a> - Button with View timeout
- <a href="/blob/main/examples/hybrid_command.lua">`hybrid_command.lua`</a> - Hybrid command (prefix + slash)
- <a href="/blob/main/examples/voice_play.lua">`voice_play.lua`</a> - Voice client usage
- <a href="/blob/main/examples/sharded_bot.lua">`sharded_bot.lua`</a> - Sharded bot with auto-sharding

## License

MIT License