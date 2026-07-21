-- spec/voice/voice_client_spec.lua
-- Tests for voice client

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

-- Mock luv for testing
local mock_luv = {
    timer = {
        new = function()
            local timer = {
                start = function() end,
                stop = function() end,
            }
            return timer
        end
    },
    socket = function()
        return 1
    end,
    bind = function() end,
    getsockname = function() end,
    onread = function() end,
    sendto = function()
        return true, nil
    end,
    recvfrom = function()
        return nil
    end,
    close = function() end,
}

package.loaded["luv"] = mock_luv

local class = require("core.class")
local emitter = require("core.emitter")

-- Mock channel
local MockChannel = class("MockChannel")
function MockChannel.new(guild)
    local self = {
        id = "channel123",
        guild = guild,
        name = "general",
    }
    setmetatable(self, MockChannel)
    return self
end

-- Mock guild
local MockGuild = class("MockGuild")
function MockGuild.new()
    local self = {
        id = "guild123",
        name = "Test Server",
    }
    setmetatable(self, MockGuild)
    return self
end

-- Mock client
local MockClient = class("MockClient")
function MockClient.new()
    local self = {
        user = {
            id = "user123",
            discriminator = "0001",
            username = "testuser",
        },
        dispatch = function() end,
    }
    setmetatable(self, MockClient)
    return self
end

local VoiceClient = require("voice.voice_client")

describe("VoiceClient", function()
    local mock_client
    local mock_channel
    local mock_guild

    before_each(function()
        mock_client = MockClient.new()
        mock_guild = MockGuild.new()
        mock_channel = MockChannel.new(mock_guild)
    end)

    describe("VoiceClient creation", function()
        it("should create a new voice client", function()
            local client = VoiceClient.new(mock_client, mock_channel)
            assert.is_not_nil(client)
            assert.equals(mock_client, client.client)
            assert.equals(mock_channel, client.channel)
            assert.equals(mock_guild, client.guild)
        end)

        it("should have state table", function()
            local client = VoiceClient.new(mock_client, mock_channel)
            assert.is_true(type(client.state) == "table")
            assert.is_false(client.state.connected)
            assert.is_false(client.state.playing)
        end)

        it("should have gateway", function()
            local client = VoiceClient.new(mock_client, mock_channel)
            assert.is_not_nil(client.gateway)
        end)

        it("should have UDP client", function()
            local client = VoiceClient.new(mock_client, mock_channel)
            assert.is_not_nil(client.udp)
        end)

        it("should have Opus encoder", function()
            local client = VoiceClient.new(mock_client, mock_channel)
            assert.is_not_nil(client.state.encoder)
        end)

        it("should have Opus decoder", function()
            local client = VoiceClient.new(mock_client, mock_channel)
            assert.is_not_nil(client.state.decoder)
        end)
    end)

    describe("Connect", function()
        local client

        before_each(function()
            client = VoiceClient.new(mock_client, mock_channel)
            client.gateway.ws = {}
            client.gateway._send = function(payload)
                return true, nil
            end
        end)

        it("should return true when connected", function()
            local success, result = pcall(function()
                return client:connect()
            end)

            assert.is_true(success)
        end)
    end)

    describe("Disconnect", function()
        local client

        before_each(function()
            client = VoiceClient.new(mock_client, mock_channel)
            client.gateway = {}
            client.udp = {}
        end)

        it("should disconnect gracefully", function()
            local success, err = pcall(function()
                client:disconnect(false)
            end)

            assert.is_true(success)
        end)

        it("should disconnect forcefully", function()
            local success, err = pcall(function()
                client:disconnect(true)
            end)

            assert.is_true(success)
        end)
    end)

    describe("Move to", function()
        local client
        local new_channel

        before_each(function()
            client = VoiceClient.new(mock_client, mock_channel)
            new_channel = MockChannel.new(mock_guild)
            new_channel.id = "channel456"
        end)

        it("should return true when connected", function()
            client.state.connected = true

            local success, err = pcall(function()
                return client:move_to(new_channel)
            end)

            assert.is_true(success)
        end)

        it("should return false when not connected", function()
            local success, err = pcall(function()
                return client:move_to(new_channel)
            end)

            assert.is_true(not success)
            assert.equals("Not connected", err)
        end)
    end)

    describe("Is connected", function()
        local client

        before_each(function()
            client = VoiceClient.new(mock_client, mock_channel)
        end)

        it("should return false when not connected", function()
            assert.is_false(client:is_connected())
        end)
    end)

    describe("Is playing", function()
        local client

        before_each(function()
            client = VoiceClient.new(mock_client, mock_channel)
        end)

        it("should return false when not playing", function()
            assert.is_false(client:is_playing())
        end)

        it("should return true when playing", function()
            client.state.playing = true
            assert.is_true(client:is_playing())
        end)
    end)

    describe("Is paused", function()
        local client

        before_each(function()
            client = VoiceClient.new(mock_client, mock_channel)
        end)

        it("should return false when not paused", function()
            assert.is_false(client:is_paused())
        end)

        it("should return true when paused", function()
            client.state.paused = true
            assert.is_true(client:is_paused())
        end)
    end)

    describe("Elapsed", function()
        local client

        before_each(function()
            client = VoiceClient.new(mock_client, mock_channel)
            client.state.elapsed = 123
        end)

        it("should return elapsed time", function()
            assert.equals(123, client:elapsed())
        end)
    end)

    describe("Send audio packet", function()
        local client

        before_each(function()
            client = VoiceClient.new(mock_client, mock_channel)
            client.udp = {
                send = function(data)
                    return true, nil
                end,
            }
        end)

        it("should encode and send packet", function()
            local packet = table.pack(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)
            local success, err = pcall(function()
                return client:send_audio_packet(packet, true)
            end)

            assert.is_true(success)
        end)

        it("should send raw packet", function()
            local packet = table.pack(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)
            local success, err = pcall(function()
                return client:send_audio_packet(packet, false)
            end)

            assert.is_true(success)
        end)

        it("should return false when encoding fails", function()
            local success, err = pcall(function()
                return client:send_audio_packet({}, true)
            end)

            assert.is_not_nil(success)
        end)
    end)

    describe("Recording", function()
        local client
        local Sink = require("voice.sinks.sink")

        before_each(function()
            client = VoiceClient.new(mock_client, mock_channel)
        end)

        it("start_recording fails when not connected", function()
            local sink = Sink.new()
            local ok, err = client:start_recording(sink, function() end)

            assert.is_false(ok)
            assert.equals("Not connected", err)
        end)

        it("start_recording succeeds when connected and sets sink.vc", function()
            client.state.connected = true
            local sink = Sink.new()

            local ok = client:start_recording(sink, function() end)

            assert.is_true(ok)
            assert.equals(client, sink.vc)
        end)

        it("start_recording fails when already recording", function()
            client.state.connected = true
            client:start_recording(Sink.new(), function() end)

            local ok, err = client:start_recording(Sink.new(), function() end)

            assert.is_false(ok)
            assert.equals("Already recording", err)
        end)

        it("_feed_recording writes into the active sink", function()
            client.state.connected = true
            local sink = Sink.new()
            client:start_recording(sink, function() end)

            client:_feed_recording("user1", "opusdata")

            assert.equals(1, sink.audio_data["user1"].packets)
        end)

        it("_feed_recording fails when not recording", function()
            local ok, err = client:_feed_recording("user1", "data")
            assert.is_false(ok)
            assert.equals("Not recording", err)
        end)

        it("stop_recording calls sink:cleanup and the finished_callback with extra args", function()
            client.state.connected = true
            local sink = Sink.new()
            local received_sink, received_arg1, received_arg2 = nil, nil, nil

            client:start_recording(sink, function(s, arg1, arg2)
                received_sink = s
                received_arg1 = arg1
                received_arg2 = arg2
            end, "channel1", "extra")

            local ok = client:stop_recording()

            assert.is_true(ok)
            assert.equals(sink, received_sink)
            assert.equals("channel1", received_arg1)
            assert.equals("extra", received_arg2)
        end)

        it("stop_recording fails when not recording", function()
            local ok, err = client:stop_recording()
            assert.is_false(ok)
            assert.equals("Not recording", err)
        end)

        it("stop_recording allows starting a new recording afterward", function()
            client.state.connected = true
            client:start_recording(Sink.new(), function() end)
            client:stop_recording()

            local ok = client:start_recording(Sink.new(), function() end)
            assert.is_true(ok)
        end)
    end)
end)
