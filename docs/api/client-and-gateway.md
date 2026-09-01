# Client and gateway

`Bot.client` is a `Client` after `Bot:connect` or `Bot:run`. Its lower-level APIs are intended for integrations and APIs not wrapped by `Bot`.

## Lifecycle and events

### `Client:start_gateway()` / `Client:stop_gateway()`

Starts or stops the `ShardManager`. `start_gateway` registers the repository's supported gateway dispatch handlers and begins automatic sharding.

### `Client:on(event, callback)` / `Client:once(event, callback)` / `Client:off(event, callback)`

Manage Client listeners. `on` and `once` return `self`; `off` removes the matching callback. `emit(event, ...)` runs listeners.

### `Client:get_application_id()`

Resolves and caches the current application ID for command synchronization.

### `Client:change_presence(opts)`

Sends a gateway presence update. `opts` is a table; its validation and exact payload serialization are handled by the client.

## Cache helpers

### `Client:get_channel(channel_id)`

Reads a channel from cache and otherwise fetches it through REST when available. It returns a model/payload according to the cached/fetched path.

### `Client:get_voice_channel_id(guild_id, user_id)`

Returns the cached channel ID from voice state or `nil`.

The client maintains channel, member, role, message, and voice-state stores as it receives supported gateway events. These stores are implementation state; prefer the helpers and models documented elsewhere.

## Application and REST helpers

The client exposes REST-backed helpers for applications, application emojis, role connection metadata, SKUs and entitlements, templates, widgets, and other model operations. They require an HTTP client and raise when called before setup. For domain-specific operations, use the documented model methods where a model is available.

## Gateway dispatches

`Client:start_gateway` emits lower-snake-case events for its explicitly wired Discord dispatches. Some construct models (`message_create`, automod, stage instance, soundboard, audit-log, entitlement, subscription); many provide raw Discord event data. Event names and callback shapes are part of the current implementation, not a complete generic Discord gateway mirror.

See [Events](../guides/events.md) and [Sharding](../guides/sharding.md).
