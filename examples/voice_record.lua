-- examples/voice_record.lua
-- Manual test: join a voice channel, record with WaveSink, write a real
-- .wav file to disk.
--
-- This exists to exercise the receive-side voice pipeline end to end on
-- a real Discord voice call, which nothing in spec/ can do (busted only
-- ever runs against mocked luv/UDP, see spec/voice/mock_luv.lua): the
-- jitter buffer (opus.PacketDecoder) reordering real out-of-order UDP
-- packets, and the Opus -> PCM decode step added to
-- VoiceClient:_feed_recording, actually decoding real RTP payloads from
-- a real speaking user via a real libopus.
--
-- Requirements to actually exercise the decode path (not just the raw
-- Opus passthrough that spec/ already covers):
--   - Run under luvit on Windows (this library's ffi/luv target), not
--     WSL/Linux, since that's where lib/voice/native_lib.lua's bundled
--     dll resolution (see lib/voice/native_lib.lua and PROG.md) applies.
--   - lib/dlls/opus-x64.dll and lib/dlls/libsodium-x64.dll present next
--     to this checkout (lib/**.dll is gitignored and only built by
--     .github/workflows/lit-publish.yml, so for a local manual test
--     either run `lit install` against a published release or copy
--     matching dlls into lib/dlls/ yourself).
--   - Another real user actually speaking in the same voice channel,
--     so the jitter buffer and decoder have real RTP traffic to work
--     with; recording a channel with nobody talking only proves the
--     command wiring, not the receive pipeline.
--
-- Usage:
--   1. Set TOKEN (or edit bot:run below).
--   2. Invite the bot to a server, join a voice channel yourself.
--   3. /record in a text channel while in that voice channel.
--   4. Talk for a few seconds.
--   5. /stoprecord - writes recording_<guild_id>.wav next to this file
--      per user who spoke, then disconnects.
--   6. Play the .wav back: real speech should be audible, not silence
--      or noise, confirming decode actually ran (see the log line this
--      prints noting whether libopus/FFI was detected).

local discord = require("../init")
local WaveSink = require("../lib/voice/sinks/wave_sink")

local intents = discord.enums.combine_intents(
    discord.enums.INTENTS.GUILDS,
    discord.enums.INTENTS.GUILD_VOICE_STATES
)

local bot = discord.Bot(nil, intents)

-- guild_id -> voice_client, tracks the one active recording per guild
-- this manual test cares about.
local active_voice_clients = {}

bot:on("ready", function()
    print("Bot is ready!")
    if bot.user then
        print("Bot ID: " .. bot.user.id)
    end

    local ffi_ok = pcall(require, "ffi")
    print("ffi available (LuaJIT): " .. tostring(ffi_ok))
    if ffi_ok then
        local opus = require("../lib/voice/opus")
        local test_decoder = opus.Decoder.new()
        local libopus_ready = test_decoder ~= nil and test_decoder.decoder ~= nil
        print("libopus loaded, real decode will run: " .. tostring(libopus_ready))
        if test_decoder and test_decoder.destroy then
            test_decoder:destroy()
        end
    else
        print("Not running under LuaJIT: recording will only capture raw Opus, not PCM")
    end
end)

bot:slash_command("record", {
    description = "Joins your voice channel and starts recording to a .wav file",
    callback = function(ctx)
        if not ctx.guild then
            ctx:respond("This command only works inside a server.")
            return
        end

        if active_voice_clients[ctx.guild.id] then
            ctx:respond("Already recording in this server. Use /stoprecord first.")
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

        local ok, voice_client_or_err = pcall(function()
            return channel:connect(bot.client)
        end)

        if not ok then
            ctx:respond("Could not connect to voice: " .. tostring(voice_client_or_err))
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
        voice_client.client:on("VOICE_CLIENT_RECONNECT_FAILED", function(data)
            print("voice reconnect failed: reason=" .. tostring(data and data.reason)
                .. " code=" .. tostring(data and data.code)
                .. " close_reason=" .. tostring(data and data.close_reason))
        end)
        voice_client.client:on("VOICE_CLIENT_SESSION_INVALIDATED", function(data)
            print("voice session invalidated: " .. tostring(data))
        end)
        voice_client.client:on("voice_state_update", function(data)
            if data and data.guild_id == ctx.guild.id then
                print("voice_state_update: user=" .. tostring(data.user_id) .. " channel=" .. tostring(data.channel_id) .. " session=" .. tostring(data.session_id))
            end
        end)
        voice_client.client:on("voice_server_update", function(data)
            if data and data.guild_id == ctx.guild.id then
                print("voice_server_update: endpoint=" .. tostring(data.endpoint) .. " token_present=" .. tostring(data.token ~= nil))
            end
        end)

        -- Voice gateway connect is async (VOICE_STATE_UPDATE +
        -- VOICE_SERVER_UPDATE round trip, see voice_client.lua's
        -- _maybe_connect_gateway), so start_recording has to wait for
        -- VOICE_CLIENT_CONNECTED rather than being called right here.
        local on_connected
        on_connected = function(connected_client)
            if connected_client ~= voice_client then
                return
            end
            bot.client:off("VOICE_CLIENT_CONNECTED", on_connected)

            local sink = WaveSink.new()
            local record_ok, record_err = voice_client:start_recording(
                sink,
                function(finished_sink)
                    local guild_id = ctx.guild.id
                    for user_id, entry in pairs(finished_sink:get_all_audio()) do
                        local filename = "recording_" .. guild_id .. "_" .. user_id .. ".wav"
                        local f = io.open(filename, "wb")
                        if f then
                            f:write(entry.file)
                            f:close()
                            print("Wrote " .. filename .. " (" .. entry.packets .. " packets)")
                        else
                            print("Failed to open " .. filename .. " for writing")
                        end
                    end
                    active_voice_clients[guild_id] = nil
                    finished_sink.vc:disconnect(true)
                end
            )

            if record_ok then
                active_voice_clients[ctx.guild.id] = voice_client
            else
                print("start_recording failed: " .. tostring(record_err))
            end
        end
        bot.client:on("VOICE_CLIENT_CONNECTED", on_connected)

        ctx:respond("Connecting and starting recording...")
    end,
})

bot:slash_command("stoprecord", {
    description = "Stops recording and writes the .wav file(s)",
    callback = function(ctx)
        if not ctx.guild then
            ctx:respond("This command only works inside a server.")
            return
        end

        local voice_client = active_voice_clients[ctx.guild.id]
        if not voice_client then
            ctx:respond("Not currently recording in this server.")
            return
        end

        local ok, err = voice_client:stop_recording()
        if ok then
            ctx:respond("Stopped recording, writing .wav file(s)...")
        else
            ctx:respond("stop_recording failed: " .. tostring(err))
        end
    end,
})

bot:run(os.getenv("TOKEN") or "YOUR_BOT_TOKEN")
