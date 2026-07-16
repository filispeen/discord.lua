-- examples/hybrid_command.lua
-- Example: Hybrid command (prefix + slash)
--
-- A hybrid command allows the same logic to be triggered via:
--   - Prefix: !hello
--   - Slash: /hello
--
-- This reduces code duplication and keeps logic in one place.

local Bot = require("discord.lua")
local BotClass = Bot

local client = BotClass("YOUR_BOT_TOKEN")

-- Hybrid command definition
local hello = {
    name = "hello",
    description = "Greet someone!",
    options = {
        {
            name = "user",
            type = "USER",
            required = true,
            description = "The user to greet",
        },
    },
    callback = function(ctx)
        local user_id = ctx.options.user.id
        local username = ctx.options.user.username
        local mention = "<@" .. user_id .. ">"

        -- Send DM to user
        client:send_dm_message(user_id, "Hello, " .. username .. "!")

        -- Reply to interaction or message
        ctx:reply("Hello, " .. mention .. "!")
    end,
}

client:add_command(hello)

client:on("ready", function()
    print("Bot is ready!")
end)

client:run()
