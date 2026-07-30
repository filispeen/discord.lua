-- spec/cache/channel_store_spec.lua
-- Tests for the channel cache, built from GUILD_CREATE/CHANNEL_CREATE/
-- CHANNEL_UPDATE/CHANNEL_DELETE payloads.

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local ChannelStore = require("./cache/channel_store")

describe("ChannelStore", function()
    it("returns nil for a channel never seen", function()
        local store = ChannelStore.new()
        assert.is_nil(store:get("channel1"))
    end)

    it("stores a channel via put", function()
        local store = ChannelStore.new()
        store:put({ id = "channel1", name = "general", type = 0, guild_id = "guild1" })

        local channel = store:get("channel1")
        assert.is_not_nil(channel)
        assert.equals("general", channel.name)
        assert.equals("guild1", channel.guild_id)
    end)

    it("ignores put with no id", function()
        local store = ChannelStore.new()
        store:put({ name = "no id" })
        store:put(nil)
        assert.is_nil(store:get("channel1"))
    end)

    it("stamps guild_id onto every channel from put_many", function()
        local store = ChannelStore.new()
        store:put_many({
            { id = "channel1", name = "general", type = 0 },
            { id = "channel2", name = "voice", type = 2 },
        }, "guild1")

        assert.equals("guild1", store:get("channel1").guild_id)
        assert.equals("guild1", store:get("channel2").guild_id)
    end)

    it("does not override an existing guild_id from put_many", function()
        local store = ChannelStore.new()
        store:put_many({
            { id = "channel1", name = "general", guild_id = "other_guild" },
        }, "guild1")

        assert.equals("other_guild", store:get("channel1").guild_id)
    end)

    it("ignores put_many with a nil channels list", function()
        local store = ChannelStore.new()
        store:put_many(nil, "guild1")
        assert.is_nil(store:get("channel1"))
    end)

    it("overwrites a channel on update", function()
        local store = ChannelStore.new()
        store:put({ id = "channel1", name = "general" })
        store:put({ id = "channel1", name = "renamed" })

        assert.equals("renamed", store:get("channel1").name)
    end)

    it("removes a channel", function()
        local store = ChannelStore.new()
        store:put({ id = "channel1", name = "general" })
        store:remove("channel1")

        assert.is_nil(store:get("channel1"))
    end)

    it("remove is a no-op for an unknown channel", function()
        local store = ChannelStore.new()
        store:remove("channel1")
        assert.is_nil(store:get("channel1"))
    end)
end)
