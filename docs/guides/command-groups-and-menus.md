# Command groups and context menus

## Slash command groups

Construct a `SlashCommandGroup` directly and register it on the bot:

```lua
local SlashCommandGroup = require("discord.lua/lib/interactions/slash_command_group")

local math = SlashCommandGroup.new("math", "Math operations")

math:command("add", "Add two numbers", function(ctx)
    ctx:respond("Use options in your command definition")
end)

bot:register_slash_command_group(math)
```

Direct subcommands can have their own option array and checks. `group:create_subgroup(name, description, options)` creates one nested subgroup level; Discord does not support deeper slash-command group nesting.

## Context menus

User and message context-menu commands use the same application-command sync path:

```lua
bot:user_command({
    name = "Show ID",
    callback = function(ctx, user)
        ctx:respond("User ID: " .. user.id, { ephemeral = true })
    end,
})

bot:message_command({
    name = "Quote",
    callback = function(ctx, message)
        ctx:respond(message.content)
    end,
})
```

The second callback parameter is the resolved target supplied by the interaction: `ctx.target_user` for a user command and `ctx.target_message` for a message command. Both accept `guild_ids` and `checks`.

Command registrations sharing the same name, type, and global/guild scope are rejected by `CommandTree:add`.
