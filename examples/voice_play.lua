-- examples/voice_play.lua
-- Example: Voice client usage.
--
-- IMPORTANT: lib/voice/voice_client.lua's connect() does not yet obtain a
-- real voice endpoint or session; VOICE_STATE_UPDATE / VOICE_SERVER_UPDATE
-- are also not wired from the gateway to Bot/Client yet, so
-- VoiceClient:connect() below will not actually join a voice channel on
-- Discord's servers. This example shows the intended shape of the API
-- and the parts that do work today (ready, bot.user, shard_ready); the
-- VoiceClient:connect() call is left in to show the intended usage once
-- voice gateway wiring lands, and is guarded with pcall so the rest of
-- the bot keeps running if it fails.

local discord = require("discord.lua")
local VoiceClient = require("voice.voice_client")

-- GUILD_VOICE_STATES is needed to track who is in which voice channel,
-- on top of GUILDS for basic guild/channel caching.
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
end)

bot:on("shard_ready", function(shard_id)
    print("Shard " .. shard_id .. " is ready")
end)

-- Slash command that attempts to join the invoking user's voice channel.
-- ctx.channel here must be a voice channel the bot can already see from
-- cache; there is no helper yet to look up "the user's current voice
-- channel" since VOICE_STATE_UPDATE is not tracked.
bot:register_application_command("join", {
    description = "Joins your voice channel",
    callback = function(ctx)
        if not ctx.channel or not ctx.channel.guild then
            ctx:respond("I need a cached voice channel with its guild to join.")
            return
        end

        local voice_client = VoiceClient.new(bot.client, ctx.channel)

        local ok, err = pcall(function()
            return voice_client:connect()
        end)

        if ok then
            ctx:respond("Connected to voice!")
        else
            ctx:respond("Could not connect to voice: " .. tostring(err))
        end
    end,
})

bot:run("YOUR_BOT_TOKEN")