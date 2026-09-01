# Components and views

Views collect interactive items and serialize them with `View:to_components()`. A view does not itself register a callback; add it with `Bot:component(view)`, or route individual custom IDs with `Bot:interaction(custom_id, callback)`.

## Safe lifecycle for the current implementation

`Bot:connect()` clears registered views and custom-ID callbacks. Therefore register them **after** `connect()` and before `client:start_gateway()`:

```lua
local discord = require("discord.lua")
local View = require("discord.lua/lib/ui/view")
local Button = require("discord.lua/lib/ui/button")

local token = assert(os.getenv("DISCORD_TOKEN"), "DISCORD_TOKEN is required")
local bot = discord.Bot.new(token, nil, discord.enums.INTENTS.GUILDS)

bot:connect()

local view = View.new({ timeout = 30000 })
view:add(Button.new({
    custom_id = "hello",
    label = "Hello",
    style = "primary",
}))

bot:interaction("hello", function(ctx)
    ctx:update("Hello from a button")
end)
bot:component(view)

bot:slash_command("button", {
    description = "Show a button",
    callback = function(ctx)
        ctx:respond("Press it", { components = view:to_components() })
    end,
})

bot.client:start_gateway()
```

!!! warning "Registration before `run()` is cleared"
    `Bot:run()` calls `Bot:connect()`, and `connect()` invokes `clear_interactions()`. The repository's `examples/view_button.lua` registers its view before `run()`, so its component handlers are removed before the gateway starts. The explicit lifecycle above matches the current code.

## View items

`View.new({ timeout = milliseconds })` owns its items. Use `view:add(item)`, `view:remove(item_or_custom_id)`, `view:find_item(custom_id)`, `view:clear()`, and `view:stop()`.

The callback dispatcher first searches active views for an item with the interaction custom ID and invokes `item.callback(ctx)` when present; it then falls back to the callback registered with `Bot:interaction`.

Button, select, input, modal, and Components v2 items are constructed from their respective modules under `discord.lua/lib/ui/`. Each intended item has `to_component()`; `View:to_components()` returns the payload shape accepted by interaction response options.

Use Discord's [message components documentation](https://discord.com/developers/docs/components/overview) for protocol limits and component types not enforced by this library.
