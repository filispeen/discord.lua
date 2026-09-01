# Slash commands

Register an application command with `Bot:slash_command`. Commands are synchronized automatically after the gateway `ready` event unless `auto_sync_commands` is disabled.

```lua
local OPTION = discord.enums.OPTION_TYPE

bot:slash_command("echo", {
    description = "Repeat text",
    options = {
        {
            name = "text",
            description = "Text to repeat",
            type = OPTION.STRING,
            required = true,
        },
    },
    callback = function(ctx)
        ctx:respond(ctx:require_arg("text"))
    end,
})
```

Each option needs a string `name` and numeric `type`. `description`, `required`, `choices`, and `autocomplete` are passed through when serializing the command. Use `ctx:get_arg(name, default)` for optional values and `ctx:require_arg(name)` for required values.

## Guild-scoped commands

Use `guild_ids` to synchronize a command into specific guilds instead of globally:

```lua
bot:slash_command("debug", {
    description = "Development command",
    guild_ids = { "123456789012345678" },
    callback = function(ctx)
        ctx:respond("OK")
    end,
})
```

## Autocomplete

`Bot:slash_command` returns an `ApplicationCommand`. Attach an autocomplete callback to an option name:

```lua
local command = bot:slash_command("search", {
    description = "Search an item",
    options = {
        { name = "query", description = "Search term", type = OPTION.STRING, required = true },
    },
    callback = function(ctx)
        ctx:respond("Submitted")
    end,
})

command:set_autocomplete("query", function(ctx)
    return {
        { name = "first", value = "first" },
        { name = "second", value = "second" },
    }
end)
```

The callback receives an `AutocompleteContext`. Its exact focused-option data is derived from the incoming interaction; keep returned choices within Discord's application-command constraints.

## Responses

The initial `ctx:respond` or `ctx:reply` call must acknowledge the interaction within Discord's three-second window. Use `ctx:defer()` followed by `ctx:edit(...)` for slower work, then use follow-up methods as needed. Details are in [Interactions and responses](interactions-and-responses.md).
