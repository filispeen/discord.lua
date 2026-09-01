# Messages and channels

## `Message`

Gateway `message_create` callbacks receive a `Message` model.

### `Message:reply(content[, opts])`

Posts a message to the current message's channel.

### `Message:edit(content[, opts])`

Edits this message.

For both methods, `content` may be a string or a payload table. `opts` can supply fields such as `embeds`, `components`, `allowed_mentions`, and `files`; when files are present, the client uses multipart HTTP.

### `Message:delete()`

Deletes the message.

### Reactions

The model maintains a `reactions` array from gateway events. Reaction mutation methods are available on the model where HTTP is attached; see the current source for less-common reaction routes.

All mutation methods raise when the message has no HTTP client.

## `Channel`

`Channel` models expose fields such as `id`, `type`, `name`, `parent_id`, `position`, `topic`, `nsfw`, and an optional `guild`.

### `Channel:get_type_name()` / `Channel:is_voice()`

Return a readable type name or whether the channel is a voice-capable channel.

### `Channel:connect(client)`

Creates a `VoiceClient` for a voice channel and starts the voice-state update. Returns the client or raises when the channel is not voice-capable, has no guild, or no `client` is supplied.

### `Channel:send_soundboard_sound(sound)`

Posts a soundboard sound in a voice channel. Raises if the channel is not voice, no HTTP client exists, or no sound is supplied.

### `Channel:create_invite(opts)` / `Channel:create_thread(...)`

Create REST resources for this channel. Their option tables are passed to the routes implemented in the library; use Discord's API reference for required permissions and route-level constraints.

## Threads

Thread models and gateway events are exposed separately from ordinary channel dispatches. `thread_create`, `thread_update`, `thread_delete`, and synchronization events update the channel cache where supported.
