# Configuration

## Constructing a bot

The package module and the class constructor take different argument layouts:

```lua
local discord = require("discord.lua")

-- Recommended package-call form: (ratelimiter, intents)
local bot = discord(nil, intents)

-- Equivalent explicit form: (token, ratelimiter, intents)
local bot2 = discord.Bot.new(nil, nil, intents)
```

`Bot:run(token)` stores the token when one is supplied and starts the HTTP and gateway clients. `Bot:connect()` only constructs and wires them; it does not start the gateway.

!!! warning "README/example constructor mismatch"
    Some repository examples use `discord.Bot(nil, intents)`. The actual `Bot.new` signature is `(token, ratelimiter, intents)`, so that form puts the intent bitfield in `ratelimiter` and leaves `intents` unset. Use one of the forms above.

## Intents

Pass a bitfield made with `discord.enums.combine_intents`:

```lua
local intents = discord.enums.combine_intents(
    discord.enums.INTENTS.GUILDS,
    discord.enums.INTENTS.GUILD_MESSAGES,
    discord.enums.INTENTS.MESSAGE_CONTENT
)

local bot = discord(nil, intents)
```

`default_intents()` excludes the privileged `GUILD_MEMBERS`, `GUILD_PRESENCES`, and `MESSAGE_CONTENT` flags. `all_intents()` includes every defined flag.

Enable any privileged intent used by your bot in the Discord Developer Portal as well. Prefix parsing reads `message.content`, so it requires `MESSAGE_CONTENT`; normal server messages also require `GUILD_MESSAGES`. Voice-channel lookup requires `GUILD_VOICE_STATES`.

## Prefix and command synchronization

The default prefix is `!`; set `bot.prefix` before dispatching messages. Application commands are synchronized automatically on `ready` because `bot.auto_sync_commands` defaults to `true`. Set it to `false` only when you will call [`Bot:sync_commands`](../api/bot.md#botsync_commands) yourself after a connection exists.

## Presence

Set `bot.status` and `bot.activity` before `run()` for the initial gateway presence. After the client exists, use `bot:change_presence(opts)`. The activity object must implement `to_dict`; activity constructors live in `lib/models/activity.lua` and are not exported by the package entry point.
