-- spec/models/client_spec.lua
-- Tests for models.client, focused on the channel cache wiring
-- (Client:get_channel, GUILD_CREATE/CHANNEL_CREATE/CHANNEL_UPDATE/
-- CHANNEL_DELETE dispatch handling).

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local Client = require("./models/client")

describe("Client:get_channel", function()
    it("returns nil when the channel is not cached and there is no rest/http", function()
        local client = Client.new("token")
        assert.is_nil(client:get_channel("channel1"))
    end)

    it("returns a Channel built from a cached raw payload", function()
        local client = Client.new("token")
        client.channels:put({ id = "channel1", name = "general", type = 0, guild_id = "guild1" })

        local channel = client:get_channel("channel1")
        assert.is_not_nil(channel)
        assert.equals("general", channel.name)
    end)

    it("attaches a minimal guild stand-in with the right id", function()
        local client = Client.new("token")
        client.channels:put({ id = "channel1", name = "voice", type = 2, guild_id = "guild1" })

        local channel = client:get_channel("channel1")
        assert.is_not_nil(channel.guild)
        assert.equals("guild1", channel.guild.id)
    end)

    it("leaves guild nil when the cached payload has no guild_id", function()
        local client = Client.new("token")
        client.channels:put({ id = "dm1", name = nil, type = 1 })

        local channel = client:get_channel("dm1")
        assert.is_nil(channel.guild)
    end)

    it("falls back to rest:get_channel when not cached", function()
        local client = Client.new("token")
        client.rest = {
            get_channel = function(_self, id)
                return { id = id, name = "from_rest", type = 0, guild_id = "guild9" }
            end,
        }

        local channel = client:get_channel("channel2")
        assert.is_not_nil(channel)
        assert.equals("from_rest", channel.name)
        assert.equals("guild9", channel.guild.id)
    end)
end)

describe("Client channel cache dispatch wiring", function()
    local function make_client_with_fake_gateway()
        local client = Client.new("token")
        local dispatch_handlers = {}

        client.gateway = {
            on_shard_ready = function() end,
            on_shard_error = function() end,
            on_shard_disconnect = function() end,
            on_ready = function() end,
            on_dispatch = function(_self, name, callback)
                dispatch_handlers[name] = callback
            end,
            start = function() end,
        }

        -- Re-run the same registration block start_gateway uses, without
        -- actually requiring gateway.manager or opening a real connection.
        local gateway_manager_stub = { new = function() return client.gateway end }
        package.loaded["gateway.manager"] = gateway_manager_stub
        client:start_gateway()
        package.loaded["gateway.manager"] = nil

        return client, dispatch_handlers
    end

    it("populates the channel cache from GUILD_CREATE", function()
        local client, handlers = make_client_with_fake_gateway()

        handlers["GUILD_CREATE"]({
            id = "guild1",
            channels = {
                { id = "channel1", name = "general", type = 0 },
                { id = "channel2", name = "voice", type = 2 },
            },
        })

        assert.equals("guild1", client.channels:get("channel1").guild_id)
        assert.equals("guild1", client.channels:get("channel2").guild_id)
    end)

    it("adds a channel from CHANNEL_CREATE", function()
        local client, handlers = make_client_with_fake_gateway()

        handlers["CHANNEL_CREATE"]({ id = "channel3", name = "new-channel", guild_id = "guild1" })

        assert.equals("new-channel", client.channels:get("channel3").name)
    end)

    it("overwrites a channel from CHANNEL_UPDATE", function()
        local client, handlers = make_client_with_fake_gateway()

        handlers["CHANNEL_CREATE"]({ id = "channel3", name = "old-name", guild_id = "guild1" })
        handlers["CHANNEL_UPDATE"]({ id = "channel3", name = "new-name", guild_id = "guild1" })

        assert.equals("new-name", client.channels:get("channel3").name)
    end)

    it("removes a channel from CHANNEL_DELETE", function()
        local client, handlers = make_client_with_fake_gateway()

        handlers["CHANNEL_CREATE"]({ id = "channel3", name = "temp", guild_id = "guild1" })
        handlers["CHANNEL_DELETE"]({ id = "channel3", guild_id = "guild1" })

        assert.is_nil(client.channels:get("channel3"))
    end)
end)
