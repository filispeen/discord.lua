-- spec/models/channel_spec.lua
-- Tests for Channel model, including Channel:connect() voice wiring

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

-- Mock luv for voice_client's transitive requires (opus/udp), same
-- approach as spec/voice/voice_client_spec.lua.
local mock_luv = {
    timer = {
        new = function()
            return {
                start = function() end,
                stop = function() end,
            }
        end
    },
    socket = function() return 1 end,
    bind = function() end,
    getsockname = function() end,
    onread = function() end,
    sendto = function() return true, nil end,
    recvfrom = function() return nil end,
    close = function() end,
}
package.loaded["luv"] = mock_luv

local Channel = require("models.channel")

describe("Channel", function()
    describe("Channel.new", function()
        it("builds fields from API data", function()
            local channel = Channel.new({ id = "1", type = 2, name = "general" })
            assert.equals("1", channel.id)
            assert.equals(2, channel.type)
            assert.equals("general", channel.name)
        end)

        it("stores guild when provided", function()
            local guild = { id = "guild1" }
            local channel = Channel.new({ id = "1", type = 2 }, guild)
            assert.equals(guild, channel.guild)
        end)

        it("leaves guild nil when not provided", function()
            local channel = Channel.new({ id = "1", type = 2 })
            assert.is_nil(channel.guild)
        end)
    end)

    describe("Channel:is_voice", function()
        it("returns true for a voice channel type", function()
            local channel = Channel.new({ id = "1", type = 2 })
            assert.is_true(channel:is_voice())
        end)

        it("returns false for a non-voice channel type", function()
            local channel = Channel.new({ id = "1", type = 1 })
            assert.is_false(channel:is_voice())
        end)
    end)

    describe("Channel:connect", function()
        it("errors when the channel is not a voice channel", function()
            local channel = Channel.new({ id = "1", type = 1 }, { id = "guild1" })
            local ok, err = pcall(function()
                channel:connect({})
            end)
            assert.is_false(ok)
            assert.is_not_nil(err:find("non%-voice"))
        end)

        it("errors when channel.guild is not set", function()
            local channel = Channel.new({ id = "1", type = 2 })
            local ok, err = pcall(function()
                channel:connect({})
            end)
            assert.is_false(ok)
            assert.is_not_nil(err:find("channel.guild"))
        end)

        it("errors when no client argument is given", function()
            local channel = Channel.new({ id = "1", type = 2 }, { id = "guild1" })
            local ok, err = pcall(function()
                channel:connect(nil)
            end)
            assert.is_false(ok)
            assert.is_not_nil(err:find("client argument"))
        end)

        it("returns a VoiceClient wired to this channel and client, on a voice channel with a guild", function()
            local guild = { id = "guild1", name = "Test" }
            local channel = Channel.new({ id = "1", type = 2, name = "general" }, guild)
            local client = { user = { id = "bot1" }, dispatch = function() end }

            -- VoiceClient:connect() sends an IDENTIFY over the voice gateway
            -- websocket; stub the transport the same way voice_client_spec does,
            -- since this test only cares about the Channel -> VoiceClient wiring.
            local voice_client_module = require("voice.voice_client")
            local original_new = voice_client_module.new
            voice_client_module.new = function(...)
                local vc = original_new(...)
                vc.gateway.ws = {}
                vc.gateway._send = function() return true end
                return vc
            end

            local voice_client = channel:connect(client)
            voice_client_module.new = original_new

            assert.is_not_nil(voice_client)
            assert.equals(client, voice_client.client)
            assert.equals(channel, voice_client.channel)
            assert.equals(guild, voice_client.guild)
        end)
    end)
end)
