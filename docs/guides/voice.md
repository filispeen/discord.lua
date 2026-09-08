# Voice

Voice connections are created from a voice `Channel`. Track the returned `VoiceClient` per guild and wait for its asynchronous gateway connection before starting recording.

```lua
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
            return ctx:respond("Use this command in a server.", { ephemeral = true })
        end

        local id = bot:get_voice_channel_id(ctx.guild.id, ctx.author.id)
        local channel = id and bot:get_channel(id)
        if not channel then
            return ctx:respond("Join a voice channel first.", { ephemeral = true })
        end

        local voice = channel:connect(bot.client)
        clients[ctx.guild.id] = voice
        ctx:respond("Connecting to voice.")
    end,
})
```

`Channel:connect` starts the voice-state update; the voice WebSocket becomes connected after the relevant `VOICE_STATE_UPDATE` and `VOICE_SERVER_UPDATE` events arrive. Listen for `VOICE_CLIENT_CONNECTED` on `bot.client` when work must wait for the completed connection.

## Playback

```lua
local started, source_or_error = voice:play_ffmpeg("audio.mp3")
if not started then
    error(source_or_error)
end

voice:pause()
voice:resume()
voice:stop()
voice:disconnect()
```

`play_ffmpeg` accepts a non-empty source string and optional FFmpeg options such as `before_options`, `options`, `loglevel`, `pipe`, and `prebuffer_frames`. It returns `true, source` or `false, error`. `set_volume(number)` works only for active PCM sources; it returns `false, message` for an inactive client, negative value, or Opus passthrough source.

## Recording

Call `start_recording(sink, finished_callback, ...)` after `VOICE_CLIENT_CONNECTED`. `WaveSink` writes decoded PCM as WAV data grouped by user; call `stop_recording()` to finalize the sink and call the completion callback.

```lua
local WaveSink = require("discord.lua/lib/voice/sinks/wave_sink")

bot.client:on("VOICE_CLIENT_CONNECTED", function(voice)
    voice:start_recording(WaveSink.new(), function(sink)
        for user_id, audio in pairs(sink:get_all_audio()) do
            local file = assert(io.open("recording-" .. user_id .. ".wav", "wb"))
            file:write(audio.file)
            file:close()
        end
    end)
end)
```

## Limitations and native dependencies

- `GUILD_VOICE_STATES` is required to find a user's voice channel through the cache.
- Playback relies on FFmpeg. On `windows-x64` and `linux-x64`, the native bundle downloads automatically the first time `discord.lua` is required; other platforms need a compatible executable discoverable by the library.
- Opus encoding/decoding, Discord voice encryption, and DAVE require native Opus, libsodium, and libdave libraries. Automatic bundles support Windows and Linux x64; see [Installation](../getting-started/installation.md#native-voice-bundle) for requirements and supported platforms.
- `VoiceClient:set_volume` cannot alter an Opus passthrough source. Use PCM/FFmpeg audio for adjustable volume.
- Connection is asynchronous. `Channel:connect` returning a `VoiceClient` does not mean the voice gateway is ready for recording or packets yet.
- DAVE support is implemented in the voice gateway through `dave_ffi`/`DaveSession`; its availability depends on the native runtime. The current code emits a `dave_unavailable` gateway event when it cannot use DAVE rather than exposing a configuration switch in `Bot`.
- Recording needs real incoming audio and a working Opus decoder. Without a native decoder, the receive-side PCM path is unavailable.
