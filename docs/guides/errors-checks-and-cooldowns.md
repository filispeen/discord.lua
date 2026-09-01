# Errors, checks, and cooldowns

Prefix command exceptions are emitted as `command_error`; application-command callback exceptions are emitted as `application_command_error`.

```lua
bot:on("command_error", function(message, err)
    print("Prefix command failed:", tostring(err))
    message:reply("Command failed.")
end)

bot:on("application_command_error", function(ctx, err)
    print("Application command failed:", tostring(err))
    ctx:respond("Command failed.", { ephemeral = true })
end)
```

Do not assume a component callback is protected by the application-command handler: the component dispatcher calls callbacks directly. Handle errors inside such callbacks when necessary.

## Checks

Checks are tables with a `func(ctx)` function. Pass an array as `checks` to `register_command`, slash-command options, bridge-command options, groups, or context menus.

```lua
local checks = require("discord.lua/lib/commands/checks")

bot:slash_command("owner", {
    description = "Owner-only command",
    checks = { checks.user("123456789012345678") },
    callback = function(ctx)
        ctx:respond("Allowed")
    end,
})
```

The module also exposes `owner`, `admin`, `staff`, `mod`, `guild`, `bot`, and `raw`. A false result suppresses the callback. The role-based helpers call `ctx.bot:get_member` and `ctx.bot:get_role`, whose current Bot implementations are placeholders; do not rely on these helpers until those lookups are implemented.

## Cooldowns

`lib/commands/cooldown.lua` provides check objects and raises `CommandOnCooldown` with `retry_after` when a command is still limited. Attach its returned value in the same `checks` array and handle the raised error in the relevant command-error event.

The public exception base types are in `lib/core/errors.lua`. Their concrete messages and fields are documented in [Enums, errors, and utilities](../api/enums-errors-and-utilities.md).
