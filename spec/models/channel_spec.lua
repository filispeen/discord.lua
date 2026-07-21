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

        it("stores an explicit http client", function()
            local http = {}
            local channel = Channel.new({ id = "1", type = 2 }, nil, http)
            assert.equals(http, channel.http)
        end)

        it("falls back to guild.http when no explicit http is given", function()
            local guild = { id = "guild1", http = {} }
            local channel = Channel.new({ id = "1", type = 2 }, guild)
            assert.equals(guild.http, channel.http)
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

    describe("Channel:send_soundboard_sound", function()
        it("errors when the channel is not a voice channel", function()
            local channel = Channel.new({ id = "1", type = 1 }, nil, {})
            assert.has_error(function()
                channel:send_soundboard_sound({ id = "sound1" })
            end)
        end)

        it("errors when no http client is attached", function()
            local channel = Channel.new({ id = "1", type = 2 })
            assert.has_error(function()
                channel:send_soundboard_sound({ id = "sound1" })
            end)
        end)

        it("errors when no sound is given", function()
            local channel = Channel.new({ id = "1", type = 2 }, nil, {})
            assert.has_error(function()
                channel:send_soundboard_sound(nil)
            end)
        end)

        it("POSTs to send-soundboard-sound with the sound's id", function()
            local calls = {}
            local http = {
                post = function(_self, endpoint, payload)
                    table.insert(calls, { endpoint = endpoint, payload = payload })
                    return {}
                end,
            }
            local channel = Channel.new({ id = "channel1", type = 2 }, nil, http)

            channel:send_soundboard_sound({ id = "sound1" })

            assert.equals(1, #calls)
            assert.equals("/channels/channel1/send-soundboard-sound", calls[1].endpoint)
            assert.equals("sound1", calls[1].payload.sound_id)
        end)

        it("includes source_guild_id when the sound belongs to a different guild", function()
            local calls = {}
            local http = {
                post = function(_self, endpoint, payload)
                    table.insert(calls, { endpoint = endpoint, payload = payload })
                    return {}
                end,
            }
            local guild = { id = "guild1", http = http }
            local channel = Channel.new({ id = "channel1", type = 2 }, guild)

            channel:send_soundboard_sound({ id = "sound1", guild_id = "other_guild" })

            assert.equals("other_guild", calls[1].payload.source_guild_id)
        end)

        it("omits source_guild_id when the sound belongs to the same guild", function()
            local calls = {}
            local http = {
                post = function(_self, endpoint, payload)
                    table.insert(calls, { endpoint = endpoint, payload = payload })
                    return {}
                end,
            }
            local guild = { id = "guild1", http = http }
            local channel = Channel.new({ id = "channel1", type = 2 }, guild)

            channel:send_soundboard_sound({ id = "sound1", guild_id = "guild1" })

            assert.is_nil(calls[1].payload.source_guild_id)
        end)
    end)

    describe("Channel:create_invite", function()
        it("errors when no http client is attached", function()
            local channel = Channel.new({ id = "1", type = 1 })
            assert.has_error(function()
                channel:create_invite()
            end)
        end)

        it("POSTs to the channel invites endpoint and returns an Invite", function()
            local calls = {}
            local http = {
                post = function(_self, endpoint, payload, opts)
                    table.insert(calls, { endpoint = endpoint, payload = payload, opts = opts })
                    return { code = "abc123" }
                end,
            }
            local channel = Channel.new({ id = "channel1", type = 1 }, nil, http)

            local invite = channel:create_invite({ max_age = 3600, max_uses = 1 })

            assert.equals(1, #calls)
            assert.equals("/channels/channel1/invites", calls[1].endpoint)
            assert.equals(3600, calls[1].payload.max_age)
            assert.equals(1, calls[1].payload.max_uses)
            assert.equals("abc123", invite.code)
        end)

        it("includes target_users_file in the payload when given", function()
            local calls = {}
            local http = {
                post = function(_self, endpoint, payload)
                    table.insert(calls, payload)
                    return { code = "abc123" }
                end,
            }
            local channel = Channel.new({ id = "channel1", type = 1 }, nil, http)

            channel:create_invite({ target_users_file = "111\n222" })

            assert.equals("111\n222", calls[1].target_users_file)
        end)

        it("omits target_users_file from the payload when not given", function()
            local calls = {}
            local http = {
                post = function(_self, endpoint, payload)
                    table.insert(calls, payload)
                    return { code = "abc123" }
                end,
            }
            local channel = Channel.new({ id = "channel1", type = 1 }, nil, http)

            channel:create_invite()

            assert.is_nil(calls[1].target_users_file)
        end)
    end)
end)
