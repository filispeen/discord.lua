# Events

Register Bot events with `bot:on(name, callback)`. `Bot` forwards a selected set of client events and dispatches prefix commands before its `message_create` listeners run.

```lua
bot:on("ready", function()
    print("The gateway is ready")
end)

bot:on("message_create", function(message)
    print(message.content)
end)
```

`bot:on_message(callback)` is an alias for `bot:on("message_create", callback)`. It observes every message seen by the gateway, including messages that match a prefix command.

## Common Bot events

| Event | Callback arguments |
|---|---|
| `ready` | none |
| `message_create` | `Message` |
| `command_error` | source `Message`, error value |
| `application_command_error` | `SlashCommandContext`, error value |
| `voice_state_update` | raw gateway payload |
| `voice_server_update` | raw gateway payload |
| `shard_ready` | event table with `shard_id` and `shard` |
| `shard_error` | event table with `shard_id`, `shard`, and `error` |
| `shard_disconnect` | event table with `shard_id`, `shard`, and `event` |

The underlying client forwards additional gateway dispatches, including message updates/deletes, reactions, member/role/channel/thread events, scheduled events, automod, soundboard, entitlement, and subscription events. Their names are lower snake case, for example `guild_member_add`, `thread_create`, and `message_poll_vote_add`; payload shape follows the code path in `Client:start_gateway` and is usually raw Discord data unless that handler constructs a model.

!!! warning "Shard callback shape"
    The current `Client` emits one table for shard lifecycle events. Do not use the positional `function(shard_id, shard, err)` form shown by `examples/sharded_bot.lua`; inspect `event.shard_id`, `event.shard`, and `event.error` instead.

## Wait for one event

`Bot:wait_for` installs a temporary listener and returns a cancellation function:

```lua
local cancel = bot:wait_for("message_create", {
    check = function(message)
        return message.content == "confirm"
    end,
    timeout = 30,
    callback = function(message)
        message:reply("Confirmed")
    end,
    on_timeout = function(err)
        print(err.message)
    end,
})

-- Call cancel() if this wait is no longer needed.
```

`timeout` is in seconds and only creates a timer when `luv` can be required. Timeout handlers receive a `TimeoutError`.
