-- lib/cache/channel_store.lua
-- Tracks known guild/DM channels, built from GUILD_CREATE (initial channel
-- list per guild) and CHANNEL_CREATE/CHANNEL_UPDATE/CHANNEL_DELETE gateway
-- dispatch events.
--
-- Public Contract:
--   ChannelStore.new(max_entries?) -> ChannelStore
--
--   ChannelStore:put(data) -> nil
--     data: a raw channel payload ({id, guild_id, type, name, ...}) as
--     received from Discord. Stores/overwrites the entry keyed by id.
--
--   ChannelStore:put_many(channels, guild_id) -> nil
--     channels: array of raw channel payloads (as sent in GUILD_CREATE's
--     .channels field, which does not include guild_id per-entry).
--     guild_id: guild id to stamp onto each entry, since Discord omits it
--     in the GUILD_CREATE channel list itself.
--
--   ChannelStore:get(channel_id) -> table or nil
--     Returns the last known raw channel payload for that id, or nil if
--     the channel has never been seen or was deleted.
--
--   ChannelStore:remove(channel_id) -> nil
--     Drops the channel from the store (CHANNEL_DELETE).

local create_cache = require("./cache/store")

local ChannelStore = {}
ChannelStore.__index = ChannelStore

function ChannelStore.new(max_entries)
    local self = setmetatable({
        cache = create_cache(max_entries or 10000),
    }, ChannelStore)
    return self
end

function ChannelStore:put(data)
    if not data or not data.id then
        return
    end
    self.cache.put(data.id, data)
end

function ChannelStore:put_many(channels, guild_id)
    if not channels then
        return
    end
    for _, channel_data in ipairs(channels) do
        if guild_id and not channel_data.guild_id then
            channel_data.guild_id = guild_id
        end
        self:put(channel_data)
    end
end

function ChannelStore:get(channel_id)
    return self.cache.get(channel_id)
end

function ChannelStore:remove(channel_id)
    self.cache.remove(channel_id)
end

return ChannelStore
