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

local discord = require("../init")
local PCMSource = require("../lib/voice/sources/pcm_source")

-- Optional: set to your test server's guild ID (as a string) to
-- register /join, /play, /leave as guild-scoped commands, which
-- Discord activates within seconds. Leave nil for global commands,
-- which can take up to an hour to propagate on first registration.
local TEST_GUILD_ID = os.getenv("TEST_GUILD_ID")
local GUILD_IDS = TEST_GUILD_ID and { TEST_GUILD_ID } or nil

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

-- Without this, an error thrown inside a slash command callback (see
-- Bot:dispatch_interaction's pcall) is swallowed silently: the command
-- appears to do nothing, no traceback is printed, and the interaction
-- is left unacknowledged (Discord then shows "This interaction failed"
-- to the user after a few seconds, with nothing in the bot's own logs
-- explaining why).
bot:on("application_command_error", function(ctx, err)
    print("Slash command error:", tostring(err))
end)

bot:on("ready", function()
    print("Bot is ready!")
    if bot.user then
        print("Bot ID: " .. bot.user.id)
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
        if TEST_GUILD_ID then
            print("Guild-scoped to:", TEST_GUILD_ID)
        end
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
    guild_ids = GUILD_IDS,
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

-- Slash command that plays the bundled test tone (examples/assets/
-- test_tone.pcm: 3s 440Hz sine, raw 16-bit 48kHz stereo PCM) through
-- the voice connection /join established for this guild. Encoding and
-- DAVE encryption (if the session negotiated it) happen inside
-- VoiceClient:play/_start_playback/send_audio_packet, this command
-- only has to hand it a source.
local function play_pcm_file(ctx, path, label)
    print("play_pcm_file invoked:", label, path)

    if not ctx.guild then
        ctx:respond("This command only works inside a server.")
        return
    end

    local voice_client = voice_clients[ctx.guild.id]
    if not voice_client then
        print("play_pcm_file: no voice_client for guild", ctx.guild.id)
        ctx:respond("Not connected to voice, use /join first.")
        return
    end

    local ok, source_or_err = pcall(PCMSource.new, path)
    if not ok then
        print("play_pcm_file: PCMSource.new failed:", tostring(source_or_err))
        ctx:respond("Could not open " .. label .. ": " .. tostring(source_or_err))
        return
    end

    local play_ok, play_err = pcall(function()
        return voice_client:play(source_or_err)
    end)

    if play_ok then
        print("play_pcm_file: playback started for", label)
        ctx:respond("Playing " .. label .. ".")
    else
        print("play_pcm_file: voice_client:play failed:", tostring(play_err))
        ctx:respond("Could not start playback: " .. tostring(play_err))
    end
end

bot:slash_command("play", {
    description = "Plays a short test tone in the connected voice channel",
    guild_ids = GUILD_IDS,
    callback = function(ctx)
        play_pcm_file(ctx, "./examples/assets/test_tone.pcm", "test tone")
    end,
})

-- Slash command that plays i_will_survive.pcm (converted from
-- examples/i_will_survive.mp3 via
-- ffmpeg -i i_will_survive.mp3 -f s16le -ar 48000 -ac 2 i_will_survive.pcm,
-- required since PCMSource only reads raw PCM, not MP3). ~4m06s.
bot:slash_command("playsong", {
    description = "Plays I Will Survive in the connected voice channel",
    guild_ids = GUILD_IDS,
    callback = function(ctx)
        play_pcm_file(ctx, "./examples/assets/i_will_survive.pcm", "I Will Survive")
    end,
})

-- Slash command that plays a 60s pure 440Hz sine tone (examples/assets/
-- test_tone_60s.pcm, generated via
-- ffmpeg -f lavfi -i "sine=frequency=440:duration=60" -f s16le -ar 48000
-- -ac 2 test_tone_60s.pcm). Long enough to judge periodic glitches with
-- an unambiguous, artifact-free signal: unlike I Will Survive (a real
-- mp3 -> pcm conversion, which could in principle carry its own
-- encoding artifacts) or the 3s test tone (too short to catch anything
-- roughly periodic), a continuous pure tone makes any actual dropout
-- immediately and unmistakably audible as a "click" or gap, with
-- nothing else in the signal to mask or be confused with it.
bot:slash_command("playtone60", {
    description = "Plays a 60s test tone in the connected voice channel",
    guild_ids = GUILD_IDS,
    callback = function(ctx)
        play_pcm_file(ctx, "./examples/assets/test_tone_60s.pcm", "60s test tone")
    end,
})

-- Slash command that disconnects from voice in this guild.
bot:slash_command("leave", {
    description = "Leaves the voice channel",
    guild_ids = GUILD_IDS,
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