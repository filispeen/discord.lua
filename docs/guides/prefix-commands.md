# Prefix commands

`Bot:command(name, callback, description)` registers a command under `bot.prefix`, which defaults to `!`.

```lua
bot.prefix = "?"

bot:command("ping", function(message)
    message:reply("Pong!")
end, "Reply with Pong!")
```

This command responds to `?ping`.

## Callback object

The callback receives a [`Message`](../api/messages-and-channels.md#message) by default, not a command context. The library does not parse positional arguments for prefix commands, so read and parse `message.content` yourself if needed.

```lua
bot:command("say", function(message)
    local text = message.content:match("^%S+%s+(.+)$")
    if text then
        message:reply(text)
    end
end)
```

### Custom prefix context

Set `bot.context_class` to a table before messages are dispatched. The object passed to the callback forwards unresolved field reads and writes to the original message, while methods on your table become available.

```lua
local Context = {}

function Context:tick()
    return self:reply("✓")
end

bot.context_class = Context

bot:command("done", function(ctx)
    ctx:tick()
end)
```

## Checks and command errors

`register_command` accepts a fifth `checks` argument; the shorthand `command` does not. Each check is a table with `func(ctx)`. A false return stops the callback; a raised error produces `command_error`.

```lua
local checks = require("discord.lua/lib/commands/checks")

bot:register_command("private", function(message)
    message:reply("Allowed")
end, bot.prefix, "Owner command", { checks.user("your-user-id") })
```

See [Errors, checks, and cooldowns](errors-checks-and-cooldowns.md) for the available helpers.

## Help command

`bot:register_help_command()` adds `!help`. It uses descriptions from registered prefix commands and is not enabled automatically.
