# Interactions and responses

Slash commands, context menus, buttons, selects, and modal submissions are Discord interactions. Their first response must be sent promptly; Discord invalidates an unacknowledged interaction after roughly three seconds.

## Slash-command response flow

```lua
bot:slash_command("slow", {
    description = "Perform deferred work",
    callback = function(ctx)
        ctx:defer()
        -- perform work without blocking the interaction acknowledgement
        ctx:edit("Finished")
    end,
})
```

`SlashCommandContext` provides:

| Method | Purpose |
|---|---|
| `respond(content, opts)` / `reply(...)` | Initial channel-message response. |
| `defer()` | Deferred channel-message response. |
| `edit(content, opts)` | Edit the original interaction response. |
| `original_response()` / `delete_original_response()` | Fetch or delete the original response. |
| `send_followup(content, opts)` | Create a follow-up and return a `Message`. |
| `fetch_followup`, `edit_followup`, `delete_followup` | Manage a follow-up by message ID. |

`opts` may contain `ephemeral`, `embeds`, `components`, and `files` for response methods that accept it. `ephemeral = true` sets the Discord ephemeral flag.

## Component responses

A component callback receives `ComponentContext`. Use `update` to replace the message containing the component, `respond` to send another message, or `defer` to acknowledge work.

```lua
bot:interaction("refresh", function(ctx)
    ctx:update("Updated")
end)
```

`ComponentContext:defer({ with_message = true })` uses a deferred channel-message response; without it, the method uses a deferred message-update response.

## Error handling

Callbacks for application commands are protected by `pcall`; failures are emitted as `application_command_error`. Component callbacks are called directly by the current dispatcher. Register error handlers and make sure every interaction path either responds, updates, or defers.
