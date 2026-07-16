-- examples/voice_play.lua
-- Example: Voice client usage
--
-- Demonstrates connecting to a voice channel and playing audio.

local Bot = require("discord.lua")
local BotClass = Bot

local client = BotClass("YOUR_BOT_TOKEN")

-- Listen for voice state updates
client:on("voice_state_update", function(before, after)
    -- Check if someone joined a voice channel
    if after.channel_id and after.member and not before.channel_id then
        print("User joined voice: " .. after.member.user.username)

        -- Create voice client
        local voice_client = client.voice_client(after.member.user.id, after.channel_id)

        -- Connect to voice channel
        local success, error = pcall(function()
            voice_client:connect()
            print("Connected to voice!")
        end)

        if not success then
            print("Error connecting:", error)
        end
    end
end)

-- Listen for ready events
client:on("ready", function()
    print("Bot is ready!")
    print("Bot ID: " .. client.user.id)
end)

-- Listen for shard ready events (auto-sharding)
client:on("shard_ready", function(shard_id)
    print("Shard " .. shard_id .. " is ready")
end)

client:run()
