# Sharding

`Client:start_gateway()` constructs a `ShardManager` and starts it. The manager requests `/gateway/bot`, uses Discord's returned recommended shard count, and limits concurrent shard starts to the session-start `max_concurrency` value.

No Bot option configures an explicit shard count in the current public API.

```lua
bot:on("shard_ready", function(event)
    print("Shard ready: " .. event.shard_id)
end)

bot:on("shard_error", function(event)
    print("Shard error: " .. tostring(event.error))
end)

bot:on("shard_disconnect", function(event)
    print("Shard disconnected: " .. event.shard_id)
end)
```

`ready` is fired once every manager shard has reported ready. The manager owns shard construction and stopping; use `bot.client:stop_gateway()` when you need to close the active manager.

!!! warning "Current callback payload"
    Bot-level shard events receive one event table, as shown above. The positional callback form used by `examples/sharded_bot.lua` does not match the current `Client:emit` calls.
