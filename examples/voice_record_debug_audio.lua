local discord = require("../init")
local WaveSink = require("../lib/voice/sinks/wave_sink")
local Sink = require("../lib/voice/sinks/sink")

local intents = discord.enums.combine_intents(
    discord.enums.INTENTS.GUILDS,
    discord.enums.INTENTS.GUILD_VOICE_STATES
)

local bot = discord.Bot(nil, intents)
local active_voice_clients = {}

local function hex_prefix(data, max_len)
    local n = math.min(#data, max_len or 32)
    local parts = {}
    for i = 1, n do
        parts[i] = string.format("%02x", data:byte(i))
    end
    return table.concat(parts, " ")
end

local function pcm_stats(data)
    local sample_count = math.floor(#data / 2)
    if sample_count == 0 then
        return nil
    end

    local min_sample = 32767
    local max_sample = -32768
    local sum_abs = 0
    local zero_crossings = 0
    local previous = nil

    for i = 1, sample_count do
        local lo, hi = data:byte(i * 2 - 1, i * 2)
        local sample = lo + hi * 256
        if sample >= 32768 then
            sample = sample - 65536
        end
        if sample < min_sample then min_sample = sample end
        if sample > max_sample then max_sample = sample end
        sum_abs = sum_abs + math.abs(sample)
        if previous ~= nil and ((previous < 0 and sample >= 0) or (previous >= 0 and sample < 0)) then
            zero_crossings = zero_crossings + 1
        end
        previous = sample
    end

    return {
        samples = sample_count,
        min = min_sample,
        max = max_sample,
        mean_abs = sum_abs / sample_count,
        zero_crossings = zero_crossings,
    }
end

local DebugWaveSink = {}
DebugWaveSink.__index = DebugWaveSink
setmetatable(DebugWaveSink, { __index = WaveSink })

function DebugWaveSink.new()
    local self = WaveSink.new()
    setmetatable(self, DebugWaveSink)
    self.debug_packets = 0
    return self
end

function DebugWaveSink:write(user_id, data)
    self.debug_packets = self.debug_packets + 1
    if self.debug_packets <= 20 then
        local stats = pcm_stats(data)
        print("PCM DEBUG packet=" .. self.debug_packets
            .. " user=" .. tostring(user_id)
            .. " bytes=" .. #data
            .. " samples=" .. tostring(stats and stats.samples)
            .. " min=" .. tostring(stats and stats.min)
            .. " max=" .. tostring(stats and stats.max)
            .. " mean_abs=" .. string.format("%.1f", stats and stats.mean_abs or 0)
            .. " zero_crossings=" .. tostring(stats and stats.zero_crossings)
            .. " hex=" .. hex_prefix(data, 16))
        io.stdout:flush()
    end
    Sink.write(self, user_id, data)
end

bot:on("ready", function()
    print("Bot is ready!")
    print("Bot ID: " .. tostring(bot.user and bot.user.id))
    local ffi_ok = pcall(require, "ffi")
    print("ffi available (LuaJIT): " .. tostring(ffi_ok))
    if ffi_ok then
        local opus = require("../lib/voice/opus")
        local decoder = opus.Decoder.new()
        print("libopus loaded, real decode will run: " .. tostring(decoder ~= nil and decoder.decoder ~= nil))
        if decoder and decoder.destroy then decoder:destroy() end
    end
end)

bot:slash_command("record", {
    description = "Joins your voice channel and starts recording with PCM diagnostics",
    callback = function(ctx)
        print("command used: /record by " .. tostring(ctx.author and ctx.author.id))
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
        voice_client.gateway:on("error", function(err) print("voice gateway error: " .. tostring(err)) end)
        voice_client.gateway:on("close", function(data) print("voice gateway closed: code=" .. tostring(data and data.code) .. " reason=" .. tostring(data and data.reason)) end)
        voice_client.gateway:on("ready", function(data) print("voice gateway ready: ssrc=" .. tostring(data and data.ssrc) .. " ip=" .. tostring(data and data.ip) .. " port=" .. tostring(data and data.port)) end)
        voice_client.gateway:on("session_description", function(data) print("voice session_description received, mode=" .. tostring(data and data.mode)) end)
        voice_client.gateway:on("dave_unavailable", function(data) print("DAVE unavailable: reason=" .. tostring(data and data.reason)) end)

        local on_connected
        on_connected = function(connected_client)
            if connected_client ~= voice_client then return end
            bot.client:off("VOICE_CLIENT_CONNECTED", on_connected)
            print("VOICE_CLIENT_CONNECTED fired, starting recording")

            local sink = DebugWaveSink.new()
            local record_ok, record_err = voice_client:start_recording(sink, function(finished_sink)
                print("finished_callback firing")
                local guild_id = ctx.guild.id
                for user_id, entry in pairs(finished_sink:get_all_audio()) do
                    local filename = "recording_debug_" .. guild_id .. "_" .. user_id .. ".wav"
                    local f = io.open(filename, "wb")
                    if f then
                        f:write(entry.file)
                        f:close()
                        print("Wrote " .. filename .. " (" .. entry.packets .. " packets)")
                    end
                end
                active_voice_clients[guild_id] = nil
                finished_sink.vc:disconnect(true)
            end)

            if record_ok then
                active_voice_clients[ctx.guild.id] = voice_client
                print("start_recording succeeded")
            else
                print("start_recording failed: " .. tostring(record_err))
            end
        end

        bot.client:on("VOICE_CLIENT_CONNECTED", on_connected)
        ctx:respond("Connecting and starting debug recording...")
    end,
})

bot:slash_command("stoprecord", {
    description = "Stops the debug recording",
    callback = function(ctx)
        print("command used: /stoprecord by " .. tostring(ctx.author and ctx.author.id))
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
        print("stoprecord: stop_recording returned ok=" .. tostring(ok) .. " err=" .. tostring(err))
        if ok then
            ctx:respond("Stopped recording, writing debug .wav file...")
        else
            ctx:respond("stop_recording failed: " .. tostring(err))
        end
    end,
})

bot:run(os.getenv("TOKEN") or "YOUR_BOT_TOKEN")
