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

-- Keyed by guild_id, holds the active VoiceClient returned by
-- Channel:connect() so /play and /leave can reuse the same connection
-- a prior /join established, instead of reconnecting.
local voice_clients = {}
local logging_bound = false

-- Without this, an error thrown inside a slash command callback (see
-- Bot:dispatch_interaction's pcall) is swallowed silently: the command
-- appears to do nothing, no traceback is printed, and the interaction
-- is left unacknowledged (Discord then shows "This interaction failed"
-- to the user after a few seconds, with nothing in the bot's own logs
-- explaining why).
bot:on("application_command_error", function(ctx, err)
    print("Slash command error:", tostring(err))
    os.exit(1)
end)

bot:on("ready", function()
    print("Bot is ready!")
    if bot.user then
        print("Bot ID: " .. bot.user.id)
    end
    if not logging_bound then
        logging_bound = true
        bot.client:on("interaction_create", function(interaction)
            print("voice interaction", interaction and interaction.data and interaction.data.name or "unknown")
        end)
        for _, event in ipairs({
            "voice_state_update", "voice_server_update", "VOICE_CLIENT_CONNECTED",
            "VOICE_CLIENT_SESSION_INVALIDATED", "VOICE_CLIENT_RECONNECT_FAILED"
        }) do
            bot.client:on(event, function(payload)
                print("voice event", event, payload and payload.channel_id or payload and payload.reason or "")
            end)
        end
    end

    -- bot.auto_sync_commands (default true) already calls this inside
    -- Bot:connect()'s own "ready" handler before this one runs, so this
    -- is a second sync, redundant by design: its only purpose is to
    -- surface a print/traceback if sync itself is failing silently,
    -- since Bot:sync_commands()/CommandTree:sync() have no pcall or
    -- logging of their own.
    local sync_ok, sync_result = pcall(function()
        return bot:sync_commands()
    end)
    if sync_ok then
        print("Slash commands synced.")
        print("Global command scope")
    else
        print("Slash command sync FAILED:", tostring(sync_result))
    end
end)

bot:on("shard_ready", function(shard_id)
    print("Shard " .. shard_id .. " is ready")
end)

-- Slash command that joins the invoking user's current voice channel.
bot:slash_command("join", {
    description = "Joins your voice channel",
    callback = function(ctx)
        print("/join invoked by", ctx.author and ctx.author.id)

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
            voice_clients[ctx.guild.id] = result
            print("/join connected, voice_client stored for guild", ctx.guild.id)
            ctx:respond("Connected to voice!")
        else
            print("/join channel:connect failed:", tostring(result))
            ctx:respond("Could not connect to voice: " .. tostring(result))
        end
    end,
})

local function http_source_options(source)
    if source:match("^https?://") then
        return {
            before_options = {
                "-reconnect", "1",
                "-reconnect_streamed", "1",
                "-reconnect_delay_max", "5",
            },
        }
    end
    return {}
end

local function play_audio(ctx)
    if not ctx.guild then
        ctx:respond("This command only works inside a server.")
        return
    end
    local source_path = ctx:require_arg("source")
    local voice_client = voice_clients[ctx.guild.id]
    if not voice_client then
        print("voice playback rejected", "no voice client")
        ctx:respond("Not connected to voice, use /join first.")
        return
    end
    print("voice source", source_path)
    local started, source_or_err = voice_client:play_ffmpeg(source_path, http_source_options(source_path))
    if not started then
        print("voice playback failed", tostring(source_or_err))
        ctx:respond("Could not play audio: " .. tostring(source_or_err))
        return
    end
    print("voice playback started", source_or_err.pid or "unknown")
    ctx:respond("Playing audio.")
end

bot:slash_command("play", {
    description = "Plays local audio or an HTTP(S) URL through FFmpeg",
    options = {
        {
            name = "source",
            type = discord.enums.OPTION_TYPE.STRING,
            description = "Local path or HTTP(S) audio URL",
            required = true,
        },
    },
    callback = function(ctx)
        play_audio(ctx)
    end,
})

bot:slash_command("volume", {
    description = "Sets active PCM audio to value percent volume",
    options = {
        {
            name = "volume",
            type = discord.enums.OPTION_TYPE.INTEGER,
            description = "Sets your volume to specified value",
            required = true,
        },
    },
    callback = function(ctx)
        local volume = ctx:require_arg("volume") / 100
        if not ctx.guild then
            ctx:respond("This command only works inside a server.")
            return
        end
        local voice_client = voice_clients[ctx.guild.id]
        if not voice_client then
            print("voice ffmpeg volume rejected", "no voice client")
            ctx:respond("Not connected to voice, use /join first.")
            return
        end
        local changed, change_err = voice_client:set_volume(volume)
        if not changed then
            print("voice volume change failed", tostring(change_err))
            ctx:respond(tostring(change_err))
            return
        end
        print("voice volume changed", volume * 100)
        ctx:respond("Volume set to " .. volume * 100 .. " percent.")
    end,
})

bot:slash_command("leave", {
    description = "Leaves the voice channel",
    callback = function(ctx)
        if not ctx.guild then
            ctx:respond("This command only works inside a server.")
            return
        end

        local voice_client = voice_clients[ctx.guild.id]
        if not voice_client then
            ctx:respond("Not connected to voice.")
            return
        end

        voice_client:stop()
        ctx:respond("Stopped.")
    end,
})

-- Slash command that disconnects from voice in this guild.
bot:slash_command("leave", {
    description = "Leaves the voice channel",
    callback = function(ctx)
        if not ctx.guild then
            ctx:respond("This command only works inside a server.")
            return
        end

        local voice_client = voice_clients[ctx.guild.id]
        if not voice_client then
            ctx:respond("Not connected to voice.")
            return
        end

        voice_client:stop()
        voice_client:disconnect()
        voice_clients[ctx.guild.id] = nil
        ctx:respond("Disconnected.")
    end,
})

bot:run(os.getenv("TOKEN") or "YOUR_BOT_TOKEN")