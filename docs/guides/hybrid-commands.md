# Hybrid commands

`Bot:bridge_command` registers the same callback as a prefix command and a slash command. Its callback receives a `BridgeContext`, not a raw `Message` or a `SlashCommandContext`.

```lua
bot:bridge_command("ping", {
    description = "Reply with Pong!",
    callback = function(ctx)
        ctx:respond("Pong!")
    end,
})
```

The prefix invocation is `!ping`; the other is `/ping` after command synchronization.

`BridgeContext.is_app` distinguishes the source. `ctx:respond` uses `Message:reply` for prefix invocations. For slash invocations it sends the initial interaction response, then edits the original response on later calls. `ctx:defer()` is a no-op for prefix commands and sends an interaction deferral for slash commands.

## Options and follow-ups

`options.options`, `options.guild_ids`, and `options.checks` configure the slash half. Prefix invocation does not parse these options, so use a separate parser if the same behavior needs arguments in both forms.

```lua
bot:bridge_command("status", {
    description = "Show the current status",
    callback = function(ctx)
        ctx:respond("Working…")
        ctx.followup:send("Done")
    end,
})
```

For an app interaction, `followup:send` creates a follow-up webhook message. For a prefix invocation, it falls back to `Message:reply`.

## Bridge groups

`Bot:bridge_group(name, options)` returns a `BridgeGroup`. Register both prefix and slash subcommands through `group:command`:

```lua
local admin = bot:bridge_group("admin", {
    description = "Administration",
})

admin:command("status", {
    description = "Show status",
    callback = function(ctx)
        ctx:respond("OK")
    end,
})
```

This exposes `!admin status` and `/admin status`. A bare prefix group callback is only registered when `invoke_without_command = true`; use `group:map_to(name)` to expose that callback as a slash subcommand, since slash groups themselves cannot be invoked.
