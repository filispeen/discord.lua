-- examples/voice_play.lua
-- Example: Voice client usage.
--
-- The voice gateway connect/reconnect/resume loop, channel cache and
-- VOICE_STATE_UPDATE/VOICE_SERVER_UPDATE wiring are all real (see
-- PROG.md's "Voice WebSocket connect loop" / "Voice reconnect" /
-- "Channel cache" sections), so /join below actually joins a channel on
-- Discord's servers. This looks up the invoking user's current voice
-- channel via Bot:get_author_voice_channel_id-equivalent for slash
-- context (guild_id/author.id), fetches the real Channel through the
-- channel cache, and connects through Channel:connect(client) exactly as
-- Channel:connect()'s public contract documents.

local discord = require("discord.lua")

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

-- Slash command that joins the invoking user's current voice channel.
bot:slash_command("join", {
    description = "Joins your voice channel",
    callback = function(ctx)
        if not ctx.guild then
            ctx:respond("This command only works inside a server.")
            return
        end

        local voice_channel_id = bot:get_voice_channel_id(ctx.guild.id, ctx.author.id)
        if not voice_channel_id then
            ctx:respond("You need to be in a voice channel first.")
            return
        end

        local channel = bot:get_channel(voice_channel_id)
        if not channel then
            ctx:respond("Could not find your voice channel in cache.")
            return
        end

        local ok, result = pcall(function()
            return channel:connect(bot.client)
        end)

        if ok then
            ctx:respond("Connected to voice!")
        else
            ctx:respond("Could not connect to voice: " .. tostring(result))
        end
    end,
})

bot:run(os.getenv("TOKEN") or "YOUR_BOT_TOKEN")