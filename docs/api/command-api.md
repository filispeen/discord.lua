# Command API

## Application commands

### `Bot:slash_command(name, options)`

Registers and returns an `ApplicationCommand`.

| `options` field | Description |
|---|---|
| `description` | Optional command description; defaults to `name`. |
| `options` | Optional dense array of slash-option tables. Each requires string `name` and numeric `type`. |
| `guild_ids` | Optional array of guild IDs, limiting synchronization scope. |
| `checks` | Optional array of check tables. |
| `callback` | Called with `SlashCommandContext`. |

### `ApplicationCommand:set_autocomplete(option_name, callback)`

Associates an autocomplete callback with an option name and returns the command. This sets the serialized `autocomplete` flag.

### `ApplicationCommand:to_dict()`

Returns the Discord application-command representation. It is used by synchronization; do not mutate the generated table and expect it to update the command object.

### `Bot:user_command(options)` / `Bot:message_command(options)`

Create context-menu commands. `options.name` is required. The callback receives `(ctx, target_user)` or `(ctx, target_message)` respectively.

## Groups

### `SlashCommandGroup.new(name, description[, options])`

Creates a group. `options.guild_ids` scopes it and `options.checks` applies to every resolved child.

### `group:command(name, description, callback[, options])`

Creates and returns a direct `ApplicationCommand` child. `options.options` is its slash-option array; `options.checks` applies to it.

### `group:create_subgroup(name, description[, options])`

Adds and returns one nested group. Its guild IDs inherit from the parent unless provided.

### `group:find(path)` / `group:to_dict()`

Resolve a sequence of subcommand names or serialize the group for Discord.

## Bridge commands

### `Bot:bridge_command(name, options)`

Registers a prefix and a slash command that call `options.callback(BridgeContext)`. `description`, `options`, `guild_ids`, and `checks` configure the slash command as well.

### `Bot:bridge_group(name, options)`

Returns a `BridgeGroup`. See `BridgeGroup:command(name, options)` and `BridgeGroup:map_to(name)` in the [hybrid guide](../guides/hybrid-commands.md).

## Prefix-only helpers

`Bot:register_command` and `Bot:command` are documented in [Bot](bot.md). `Command` and `Group` modules provide metadata containers, but registration and dispatch are driven by `Bot`'s name-to-callback tables; they are not decorator APIs.
