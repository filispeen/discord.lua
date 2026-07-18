-- examples/hybrid_command.lua
-- Example: Hybrid command (prefix + slash).
--
-- A hybrid command allows the same logic to be triggered via:
--   - Prefix: !ping
--   - Slash: /ping
--
-- This reduces code duplication and keeps logic in one place. There is
-- no single "hybrid" registration helper, so the same handler is passed
-- to both register_command and register_application_command.

local Bot = require("discord.lua")
local enums = require("core.enums")

local bot = Bot("YOUR_BOT_TOKEN")

bot:on("ready", function()
    print("Bot is ready!")
end)

local function ping(ctx)
    ctx:reply("Pong!")
end

bot:register_command("ping", ping, "!", "Replies with pong")
bot:register_application_command("ping", {
    description = "Replies with pong",
    callback = ping,
})

-- A slash-only command with an option.
-- ctx.args.user holds the parsed User option.
bot:register_application_command("greet", {
    description = "Greet someone",
    options = {
        {
            name = "user",
            type = enums.OPTION_TYPE.USER,
            description = "The user to greet",
            required = true,
        },
    },
    callback = function(ctx)
        local user = ctx:require_arg("user")
        ctx:respond("Hello, <@" .. user.id .. ">!")
    end,
})

bot:run()
