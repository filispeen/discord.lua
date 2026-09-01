# Guilds, members, users, and roles

## `Guild`

Guild models carry Discord guild data plus attached HTTP/client references where created from REST or caches.

### `Guild:fetch_scheduled_event(event_id[, with_user_count])`

Fetches and returns a `ScheduledEvent`. `with_user_count` defaults to true. Raises without an HTTP client.

### `Guild:create_scheduled_event(opts)`

Creates and returns a `ScheduledEvent`.

| Required field | Description |
|---|---|
| `opts.name` | Event name. |
| `opts.start_time` | Scheduled start time accepted by Discord. |
| `opts.channel_id` or `opts.location` | Voice/stage channel or external-event location. |

Optional fields include `end_time`, `description`, `privacy_level`, `entity_type`, and `reason`. Raises when required values or HTTP are absent.

Guild also exposes REST-backed automod, channel, role, emoji, sticker, soundboard, template, widget, integration, stage-instance, welcome-screen, and scheduled-event operations implemented in its source.

## `Member`

### `Member:has_role(role)`

Returns true when one of the member's role entries has the same `id` or `name` as `role`.

### `Member:get_role_id(role)`

Returns the matching role ID or `nil`.

Member fields include `user`, `roles`, `joined_at`, `deaf`, `mute`, `pending`, and `nick`. Gateway caches may hold raw member-shaped data instead of this wrapper in some paths.

## `User`

`User` fields include `id`, `username`, `discriminator`, `global_name`, `avatar`, `avatar_asset`, `bot`, `system`, locale, flags, banner, and optional primary-guild/collectible data.

### `User:get_display_name()`

Returns the username for bot users, otherwise `username .. "#" .. discriminator`.

## Roles and permissions

Role and permission models are used by guild/cache and REST APIs. `discord.Permissions` exposes the permission wrapper, and `lib/models/permission.lua` contains bit/permission helpers. Use the numeric Discord permission bits accepted by the current model; do not assume role lookups through `Bot:get_role`, which currently returns `nil`.
