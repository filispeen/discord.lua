-- examples/lavalink_integration/bot.lua
-- Example: playing music via filispeen/lavalink.lua on top of discord.lua.
--
-- Requires (via lit):
--   lit install filispeen/lavalink.lua

local Bot = require("discord.lua")
local lavalinklua = require("lavalink.lua")
local createDiscordLuaIntegration = require("lavalink_integration.discord_lua")

local bot = Bot("YOUR_BOT_TOKEN")

local lavalink

bot:on("ready", function()
    lavalink = createDiscordLuaIntegration(bot, {
        nodes = {
            {
                id = "main",
                host = "localhost",
                port = 2333,
                authorization = "youshallnotpass",
            },
        },
    })

    lavalink:on("trackStart", function(_player, track)
        print("Now playing: " .. track.info.title)
    end)

    lavalink:on("queueEnd", function(player)
        player:destroy("queue finished")
    end)

    lavalink:init()
end)

bot:register_application_command("play", {
    description = "Plays a track in your voice channel",
    options = {
        { name = "query", type = 3, description = "Search query or URL", required = true },
    },
    callback = function(ctx)
        local query = ctx:require_arg("query")

        if not ctx.guild_id or not ctx.channel then
            ctx:respond("This command only works in a server.")
            return
        end

        local player, created = lavalink:createPlayer({
            guildId = ctx.guild_id,
            voiceChannelId = ctx.channel.id,
            textChannelId = ctx.channel.id,
            selfDeaf = true,
        })
        if created then
            player:connect()
        end

        local result = lavalink:search(query)
        if not result or not result.data or not result.data[1] then
            ctx:respond("No results found for: " .. query)
            return
        end

        player.queue:add(result.data[1])
        player:play()

        ctx:respond("Queued: " .. result.data[1].info.title)
    end,
})

bot:run()
