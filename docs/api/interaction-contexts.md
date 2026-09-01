# Interaction contexts

## `SlashCommandContext`

Application-command callbacks receive a context that copies interaction fields and provides parsed arguments.

### `ctx:get_arg(name[, default])`

Returns the parsed argument value if truthy; otherwise returns `default`.

### `ctx:require_arg(name)`

Returns the parsed argument value or raises `Missing required argument: <name>`.

### Responses

`respond`, `reply`, `defer`, `edit`, `original_response`, `delete_original_response`, `send_followup`, `fetch_followup`, `edit_followup`, and `delete_followup` are described in [Interactions and responses](../guides/interactions-and-responses.md).

## `ComponentContext`

Component callbacks receive a context that copies the raw interaction and exposes:

| Field | Description |
|---|---|
| `custom_id` | `interaction.data.custom_id`. |
| `component_type` | `interaction.data.component_type`. |
| `values` | `interaction.data.values`, when supplied. |
| `interaction_id` / `interaction_token` | Values used to create the interaction response. |

### `ctx:respond(content[, opts])`

Sends an interaction channel message (response type 4).

### `ctx:update(content[, opts])`

Updates the source message (response type 7).

### `ctx:defer([opts])`

Defers the message update (type 6), or a channel-message response (type 5) when `opts.with_message` is true.

All three raise when the client has no REST interface.

## `BridgeContext`

Bridge callbacks receive `author`, `guild`, `channel`, `bot`, `args`, `is_app`, and `followup`. It normalizes response methods across prefix and slash commands. See [Hybrid commands](../guides/hybrid-commands.md) for the differing behavior.
