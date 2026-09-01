# Bot

`Bot` is the high-level entry point for gateway lifecycle, commands, and Bot-level event listeners.

## Construction

### `discord(ratelimiter, intents)`

Creates `Bot.new(nil, ratelimiter, intents)`.

| Parameter | Description |
|---|---|
| `ratelimiter` | Optional table/object passed to the client. |
| `intents` | Optional numeric gateway intent bitfield. |

### `Bot.new(token, ratelimiter, intents)`

Creates a Bot directly. `token` may be supplied here or later to `run`.

The new bot has prefix `!`, `auto_sync_commands = true`, empty command/listener tables, and no client until `connect` or `run`.

## Lifecycle

### `Bot:connect()`

Creates the underlying `Client`, HTTP client, and event wiring. Returns `self`. It does not start the gateway.

It clears `interactions` and `components` before creating the client. Register component callbacks only after this call.

### `Bot:run([token])`

Stores optional `token`, calls `connect`, starts the gateway, and returns `self`. Errors raised while connecting or starting are re-raised.

### `Bot:sync_commands()`

Synchronizes the current application command tree. Returns the command-tree sync result.

Raises an error before `connect`, or when no application ID can be resolved.

### `Bot:change_presence(opts)`

Delegates live presence changes to the underlying client. `opts` is passed through to `Client:change_presence`.

Raises an error before `connect` or `run`.

## Events

### `Bot:on(event, callback)`

Registers `callback` for a Bot event and returns `self`.

### `Bot:on_message(callback)`

Registers a `message_create` callback and returns `self`. The callback receives every gateway `Message`, including command messages.

### `Bot:wait_for(event_name, opts)`

Installs a temporary listener and returns `cancel()`. `opts.check` defaults to a function returning true; `opts.callback` runs when it passes. `opts.timeout` is seconds, and `opts.on_timeout` receives a `TimeoutError` when a Luv timer is available.

### `Bot:emit(event, ...)`

Runs registered Bot listeners and returns `self`. This is primarily useful when integrating a custom event source.

## Prefix commands

### `Bot:command(name, callback[, description])`

Registers a prefix command with the current `bot.prefix`; returns `self`. `callback` receives a `Message` unless `context_class` is configured.

### `Bot:register_command(name, callback, prefix[, description[, checks]])`

Registers a prefix command unless that name already exists. `checks` is an array of tables containing `func(ctx)`.

### `Bot:unregister_command(name)`

Removes the prefix command and associated metadata.

### `Bot:register_help_command()`

Registers a `help` prefix command and returns `self`.

### `Bot:generate_help_text([command_name])`

Returns help text for one registered command or for all prefix commands, sorted by name.

## Context helpers

### `Bot:get_context(message[, class])`

Returns `message` by default. If a context class/table is provided directly or through `bot.context_class`, returns a forwarding wrapper whose methods come from that table.

### `Bot:get_application_context(interaction[, class])`

Creates the slash/application context. Uses `bot.application_context_class` when no explicit class is supplied.

### `Bot:get_channel(channel_id)` / `Bot:get_user(user_id)`

Delegate to the current client. `get_channel` returns `nil` before a client exists.

### `Bot:get_voice_channel_id(guild_id, user_id)`

Returns the cached voice channel ID or `nil`. Requires `GUILD_VOICE_STATES` and observed gateway events.

### `Bot:get_author_voice_channel_id(message)`

Returns the message author's cached voice channel ID, or `nil` in a DM or when the state is unavailable.

## Messages and models

### `Bot:embed(data)`

Returns a new `Embed`.

### `Bot:edit_message(guild_id, channel_id, message_id, payload)`

Edits a channel message. `guild_id` is accepted but is not part of the HTTP route. Raises before a connected HTTP client exists.

### `Bot:fetch_default_sounds()`

Fetches Discord default soundboard sounds and returns an array of `Sound` models. Raises before an HTTP client exists.

## Components

### `Bot:component(view)`

Registers a `View` for custom-ID dispatch and returns `self`.

### `Bot:interaction(custom_id, callback)`

Registers `callback(ComponentContext)` for a custom ID and returns `self`. A matching active view item takes precedence over this callback.

### `Bot:clear_interactions()`

Clears all view and custom-ID registrations and returns `self`. `connect()` calls it automatically; see [Components and views](../guides/components-and-views.md).

## Extensions and cogs

`add_cog(cog)`, `remove_cog(cog)`, `load_extension(name)`, `unload_extension(name)`, and `reload_extension(name)` are described in [Extensions, cogs, and tasks](../guides/extensions-cogs-and-tasks.md).
