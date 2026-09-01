# Voice API

## `VoiceClient`

Instances are returned by `Channel:connect(client)`.

### State

`is_connected()`, `is_playing()`, and `is_paused()` return the corresponding current state booleans. `elapsed()` returns the tracked elapsed playback value.

### `voice:connect()` / `voice:disconnect([force])`

`connect` sends the gateway voice-state update and returns true. `disconnect` leaves the channel, closes socket resources, resets playback state, and returns true. `force` additionally stops jitter/keepalive resources.

### `voice:move_to(channel)`

Moves to a different voice channel through the client gateway. The target must be a compatible channel in the same voice workflow.

### `voice:play(source[, options])`

Starts a source when the voice client is connected. Returns `true` on start or `false, "Not connected"`.

### `voice:play_ffmpeg(source[, opts])`

Creates `FFmpegAudioSource` and starts it. Returns `true, source_object` or `false, error_message`.

### `voice:set_volume(volume)`

Changes an active PCM source volume. Returns `true`, or `false, reason`; it rejects negative values, inactive playback, and Opus passthrough.

### `voice:stop()` / `voice:pause()` / `voice:resume()`

Control playback and return true. `stop` also cleans the active source.

### `voice:start_recording(sink, finished_callback, ...)`

Starts receiving audio into `sink` and stores extra callback arguments. See [Voice](../guides/voice.md#recording) for required connection timing.

### `voice:stop_recording()`

Finalizes the active sink and invokes its completion callback. Returns `true`, or `false, "Not recording"`.

## Sources and sinks

`AudioSource` is the base interface with `read`, `is_playing`, `is_opus`, and `cleanup`. Intended built-ins include `PCMSource`, `FFmpegAudioSource`, and `FFmpegOpusSource`.

`Sink` provides `get_all_audio()` and `get_user_audio(user_id)`. `WaveSink`, `PCMSink`, and `OpusSink` are intended recording outputs. Load them from `discord.lua/lib/voice/sources/...` or `discord.lua/lib/voice/sinks/...`.

`FFmpegOpusSource` is passthrough-oriented and has `probe`/`from_probe`; its output cannot be volume-adjusted by `VoiceClient:set_volume`.
