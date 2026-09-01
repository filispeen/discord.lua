# Extensions, cogs, and tasks

## Extensions

An extension is a Lua module returning a table with `setup(bot)`. `setup` may return a cleanup function; a module-level `teardown(bot)` takes precedence when unloading.

```lua
-- my_extension.lua
return {
    setup = function(bot)
        bot:command("hello", function(message)
            message:reply("Hello")
        end)

        return function(_bot)
            -- release extension-owned resources
        end
    end,
}
```

```lua
bot:load_extension("my_extension")
bot:reload_extension("my_extension")
bot:unload_extension("my_extension")
```

`load_extension` snapshots command, listener, application-command, view, and interaction registration tables. A setup failure restores that snapshot and removes the module from `package.loaded`.

## Cogs

`lib/commands/cog.lua` provides an opt-in convention. Methods named `command_name` are registered as prefix commands, while methods named `on_event` become Bot listeners.

```lua
local Cog = require("discord.lua/lib/commands/cog")
local greetings = Cog.new("greetings")

function greetings.command_hi(message)
    message:reply("Hi")
end

function greetings.on_ready()
    print("Cog ready")
end

greetings:register_commands(bot, bot.prefix)
greetings:register_listeners(bot)
bot:add_cog(greetings)
```

## Repeating tasks

`lib/ext/tasks.lua` exports `tasks.loop`. It accepts a callback plus interval options (`seconds`, `minutes`, or `hours`), or an absolute `time` string/table. Returned loops support `start`, `stop`, `cancel`, `change_interval`, lifecycle hooks, and retry exception matchers.

```lua
local tasks = require("discord.lua/lib/ext/tasks")

local heartbeat = tasks.loop(function()
    print("tick")
end, { minutes = 1 })

heartbeat:error(function(err)
    print("Task failed:", err)
end)

heartbeat:start()
```
