# Voice

The example joins the invoking user's cached voice channel and then plays a source through FFmpeg.

```lua
local discord = require("discord.lua")
local OPTION = discord.enums.OPTION_TYPE

local intents = discord.enums.combine_intents(
    discord.enums.INTENTS.GUILDS,
    discord.enums.INTENTS.GUILD_VOICE_STATES
)
local bot = discord(nil, intents)
local clients = {}

bot:slash_command("join", {
    description = "Join your voice channel",
    callback = function(ctx)
        if not ctx.guild then
            return ctx:respond("Use this in a server.", { ephemeral = true })
        end

        local channel_id = bot:get_voice_channel_id(ctx.guild.id, ctx.author.id)
        local channel = channel_id and bot:get_channel(channel_id)
        if not channel then
            return ctx:respond("Join a voice channel first.", { ephemeral = true })
        end

        clients[ctx.guild.id] = channel:connect(bot.client)
        ctx:respond("Connecting.")
    end,
})

bot:slash_command("play", {
    description = "Play a local file or URL with FFmpeg",
    options = {
        {
            name = "source",
            description = "Path or URL",
            type = OPTION.STRING,
            required = true,
        },
    },
    callback = function(ctx)
        local voice = ctx.guild and clients[ctx.guild.id]
        if not voice then
            return ctx:respond("Use /join first.", { ephemeral = true })
        end

        local ok, source_or_err = voice:play_ffmpeg(ctx:require_arg("source"))
        if not ok then
            return ctx:respond("Playback failed: " .. source_or_err, { ephemeral = true })
        end
        ctx:respond("Playback started.")
    end,
})

bot:run(assert(os.getenv("DISCORD_TOKEN"), "DISCORD_TOKEN is required"))
```

`/play` can be issued before the asynchronous voice connection is complete; in that case `play_ffmpeg` returns `false, "Not connected"`. For a production recording flow, wait for `VOICE_CLIENT_CONNECTED` as shown in the [voice guide](../guides/voice.md#recording).
