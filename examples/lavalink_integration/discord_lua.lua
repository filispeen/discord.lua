-- integrations/discord_lua.lua
-- Integration shim wiring filispeen/lavalink.lua to this library (discord.lua),
-- mirroring the shape of lavalink.lua's own integrations/discordia.lua.
--
-- Usage:
--
--   local Bot = require("discord.lua")
--   local lavalinklua = require("lavalink.lua")
--   local createDiscordLuaIntegration = require("lavalink.lua.integrations.discord_lua")
--
--   local bot = Bot("TOKEN")
--
--   bot:on("ready", function()
--       local lavalink = createDiscordLuaIntegration(bot, {
--           nodes = {
--               { id = "main", host = "localhost", port = 2333, authorization = "youshallnotpass" },
--           },
--       })
--
--       lavalink:on("trackStart", function(player, track)
--           print("Now playing: " .. track.info.title)
--       end)
--
--       lavalink:init()
--   end)
--
--   bot:run()
--
-- Public Contract:
--   createDiscordLuaIntegration(bot, lavalinkOptions) -> LavalinkManager
--     bot: a discord.lua Bot instance, already past "ready" (so bot.user
--     is populated) and already connected (bot:connect() / bot:run()).
--     lavalinkOptions: the same options table LavalinkManager.new expects;
--     clientId and sendPayload are filled in here if not already set.

local LavalinkManager = require("libs.LavalinkManager")

local function createDiscordLuaIntegration(bot, lavalink_options)
    assert(bot, "[discord.lua] bot required")
    assert(lavalink_options, "[discord.lua] lavalinkOptions required")

    lavalink_options.clientId = lavalink_options.clientId
        or (bot.user and bot.user.id)
        or error("[discord.lua] clientId required (call after \"ready\", or pass clientId explicitly)", 0)

    -- discord.lua already resolves which shard owns a guild and sends
    -- opcode 4 itself (Client:voice_state_update -> ShardManager
    -- -> Shard:voice_state_update), so sendPayload here only needs to
    -- unwrap Lavalink's {op, d} envelope and hand off the fields.
    lavalink_options.sendPayload = lavalink_options.sendPayload or function(guild_id, payload)
        if not bot.client then
            error("[discord.lua] bot has no client, call bot:connect() or bot:run() first", 0)
        end

        local d = payload.d or {}
        bot.client:voice_state_update(
            d.guild_id or guild_id,
            d.channel_id,
            d.self_mute or false,
            d.self_deaf or false
        )
    end

    local manager = LavalinkManager.new(lavalink_options)

    -- discord.lua already dispatches VOICE_STATE_UPDATE / VOICE_SERVER_UPDATE
    -- as their own structured events (no raw JSON string to decode here,
    -- unlike Discordia's "raw" event).
    bot:on("voice_state_update", function(data)
        manager:handleVoiceUpdate({ t = "VOICE_STATE_UPDATE", d = data })
    end)

    bot:on("voice_server_update", function(data)
        manager:handleVoiceUpdate({ t = "VOICE_SERVER_UPDATE", d = data })
    end)

    return manager
end

return createDiscordLuaIntegration
