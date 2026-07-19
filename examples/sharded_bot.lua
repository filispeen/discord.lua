-- examples/sharded_bot.lua
-- Example: Sharded bot lifecycle events.
--
-- Sharding itself (how many shards, which guilds go to which shard) is
-- handled automatically by ShardManager:start(), based on Discord's
-- recommended shard count from GET /gateway/bot. There is nothing to
-- configure here beyond listening to the lifecycle events below.

local Bot = require("discord.lua")

-- bot:command("ping", ...) below is a prefix command, so it needs
-- GUILD_MESSAGES to see the message and MESSAGE_CONTENT (privileged,
-- enable it on the dev portal too) to read the text.
local intents = Bot.enums.combine_intents(
    Bot.enums.INTENTS.GUILDS,
    Bot.enums.INTENTS.GUILD_MESSAGES,
    Bot.enums.INTENTS.MESSAGE_CONTENT
)

local bot = Bot(nil, intents)

-- Fires once every shard has reported READY.
bot:on("ready", function()
    print("Bot is ready!")
    if bot.user then
        print("Logged in as " .. bot.user.username)
    end
end)

-- Fires once per shard, as each one finishes its own READY handshake.
bot:on("shard_ready", function(shard_id)
    print("Shard " .. shard_id .. " is ready")
end)

bot:on("shard_disconnect", function(shard_id)
    print("Shard " .. shard_id .. " disconnected")
end)

bot:on("shard_error", function(shard_id, _shard, err)
    print("Shard " .. shard_id .. " errored: " .. tostring(err))
end)

bot:command("ping", function(msg)
    msg:reply("Pong!")
end, "Replies with pong")

bot:run("YOUR_BOT_TOKEN")