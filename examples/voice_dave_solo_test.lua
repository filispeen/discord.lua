-- examples/voice_dave_solo_test.lua
-- Manual test: bot connects alone to a fixed voice channel, no other
-- real user present, to check whether the 4020 close after MLS_WELCOME
-- + key ratchet switch happens even without a second committing member.

local discord = require("../init")

local CHANNEL_ID = "1432435826473701530"

local intents = discord.enums.combine_intents(
    discord.enums.INTENTS.GUILDS,
    discord.enums.INTENTS.GUILD_VOICE_STATES
)

local bot = discord.Bot(nil, intents)

bot:on("ready", function()
    print("Bot is ready!")
    if bot.user then
        print("Bot ID: " .. bot.user.id)
    end

    local channel = bot:get_channel(CHANNEL_ID)
    if not channel then
        print("Could not find channel " .. CHANNEL_ID .. " in cache.")
        return
    end

    local ok, voice_client_or_err = pcall(function()
        return channel:connect(bot.client)
    end)

    if not ok then
        print("Could not connect to voice: " .. tostring(voice_client_or_err))
        return
    end

    local voice_client = voice_client_or_err

    voice_client.gateway:on("error", function(err)
        print("voice gateway error: " .. tostring(err))
    end)
    voice_client.gateway:on("close", function(data)
        print("voice gateway closed: code=" .. tostring(data and data.code) .. " reason=" .. tostring(data and data.reason))
    end)
    voice_client.gateway:on("ready", function(data)
        print("voice gateway ready: ssrc=" .. tostring(data and data.ssrc) .. " ip=" .. tostring(data and data.ip) .. " port=" .. tostring(data and data.port))
    end)
    voice_client.gateway:on("session_description", function(data)
        print("voice session_description received, mode=" .. tostring(data and data.mode))
    end)
    bot.client:on("VOICE_CLIENT_RECONNECT_FAILED", function(data)
        print("voice reconnect failed: reason=" .. tostring(data and data.reason)
            .. " code=" .. tostring(data and data.code)
            .. " close_reason=" .. tostring(data and data.close_reason))
    end)
    bot.client:on("VOICE_CLIENT_SESSION_INVALIDATED", function(data)
        print("voice session invalidated: " .. tostring(data))
    end)
    bot.client:on("VOICE_CLIENT_CONNECTED", function(connected_client)
        if connected_client == voice_client then
            print("VOICE_CLIENT_CONNECTED fired, DAVE handshake and voice pipe up.")
        end
    end)
end)

bot:run(os.getenv("TOKEN") or "YOUR_BOT_TOKEN")
