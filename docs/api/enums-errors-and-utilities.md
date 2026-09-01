# Enums, errors, and utilities

## `discord.enums`

### `INTENTS`

Name-to-bit table containing:

`GUILDS`, `GUILD_MEMBERS`, `GUILD_MODERATION`, `GUILD_EMOJIS_AND_STICKERS`, `GUILD_INTEGRATIONS`, `GUILD_WEBHOOKS`, `GUILD_INVITES`, `GUILD_VOICE_STATES`, `GUILD_PRESENCES`, `GUILD_MESSAGES`, `GUILD_MESSAGE_REACTIONS`, `GUILD_MESSAGE_TYPING`, `DIRECT_MESSAGES`, `DIRECT_MESSAGE_REACTIONS`, `DIRECT_MESSAGE_TYPING`, `MESSAGE_CONTENT`, `GUILD_SCHEDULED_EVENTS`, `AUTO_MODERATION_CONFIGURATION`, `AUTO_MODERATION_EXECUTION`, `GUILD_MESSAGE_POLLS`, and `DIRECT_MESSAGE_POLLS`.

### `combine_intents(...)`

Returns the bitwise OR of numeric intent values.

### `default_intents()` / `all_intents()`

Return non-privileged intents or every defined intent. Privileged values are `GUILD_MEMBERS`, `GUILD_PRESENCES`, and `MESSAGE_CONTENT`.

### `OPTION_TYPE`

Slash option constants: `SUB_COMMAND`, `SUB_COMMAND_GROUP`, `STRING`, `INTEGER`, `BOOLEAN`, `USER`, `CHANNEL`, `ROLE`, `MENTIONABLE`, `NUMBER`, and `ATTACHMENT`.

### `ACTIVITY_TYPE`

Activity constants: `PLAYING`, `STREAMING`, `LISTENING`, `WATCHING`, `CUSTOM`, and `COMPETING`.

## Errors

`lib/core/errors.lua` defines library exception objects, including `TimeoutError`. `lib/commands/cooldown.lua` defines `CommandOnCooldown.new(retry_after)`, whose `retry_after` property is seconds and whose string form includes the retry duration.

The code raises Lua errors rather than returning a uniform result object for many invalid states. Use `pcall` at integration boundaries, and use Bot command-error events for dispatched callbacks.

## Tasks

`tasks.loop(callback, opts)` and `tasks.loop(opts)(callback)` create repeating `Loop` objects. Options support positive `seconds`, `minutes`, or `hours`; `time` accepts `HH:MM[:SS]`, `{ hour, minute, second }`, or a non-empty list; `count`, `reconnect`, retry exceptions, and backoff values are also accepted.

`Loop` methods include `start`, `stop`, `cancel`, `is_running`, `change_interval`, `before_loop`, `after_loop`, `error`, `add_exception_type`, and `clear_exception_types`.
