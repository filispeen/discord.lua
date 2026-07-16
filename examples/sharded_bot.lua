-- examples/sharded_bot.lua
-- Example: Sharded bot with auto-sharding
--
-- Demonstrates using the ShardManager for handling multiple shards.
-- The manager automatically fetches shard count and max_concurrency
-- from /gateway/bot and spawns shards accordingly.

local Bot = require("discord.lua")
local BotClass = Bot

local client = BotClass("YOUR_BOT_TOKEN")

-- Shard manager handles auto-sharding automatically
client.on_ready(function()
    -- ShardManager manages shards internally
    -- Just listen for shard ready events
    client.on_shard_ready(function(shard_id)
        print("Shard " .. shard_id .. " is ready")
    end)

    client.on_shard_error(function(shard_id, error)
        print("Shard " .. shard_id .. " error:", error)
    end)

    client.on_shard_disconnect(function(shard_id)
        print("Shard " .. shard_id .. " disconnected")
    end)
end)

-- Add a simple command to all shards
client:command("ping", function(msg)
    msg:reply("Pong! (Shard " .. msg.shard_id .. "/" .. msg.shard_count .. ")")
end)

client:command("info", function(msg)
    local shard_info = {
        shard = msg.shard_id,
        total = msg.shard_count,
        guilds = msg.guild_count or "unknown",
        users = msg.member_count or "unknown",
    }

    msg:reply(
        "Bot Info:\n" ..
        "  Shard: " .. shard_info.shard .. "/" .. shard_info.total .. "\n" ..
        "  Guilds: " .. shard_info.guilds .. "\n" ..
        "  Users: " .. shard_info.users
    )
end)

client:on("ready", function()
    print("Bot is ready!")
    print("User: " .. client.user.username .. "#" .. client.user.discriminator)
    print("ID: " .. client.user.id)
end)

client:run()
