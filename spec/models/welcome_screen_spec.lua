-- spec/models/welcome_screen_spec.lua
-- Tests for WelcomeScreen and WelcomeScreenChannel models

require("spec_helper")

local WelcomeScreenModule = require("./models/welcome_screen")
local WelcomeScreen = WelcomeScreenModule.WelcomeScreen
local WelcomeScreenChannel = WelcomeScreenModule.WelcomeScreenChannel

local function fake_http()
    local calls = {}
    return {
        calls = calls,
        get = function(_self, endpoint)
            table.insert(calls, { method = "GET", endpoint = endpoint })
            return {
                description = "Welcome!",
                welcome_channels = {
                    { channel_id = "c1", description = "Read the rules", emoji_id = nil, emoji_name = "wave" },
                },
            }
        end,
        patch = function(_self, endpoint, payload, opts)
            table.insert(calls, { method = "PATCH", endpoint = endpoint, payload = payload, opts = opts })
            return {
                description = payload.description or "Welcome!",
                welcome_channels = payload.welcome_channels or {},
            }
        end,
    }
end

local function screen_payload()
    return {
        description = "Welcome to the server!",
        welcome_channels = {
            { channel_id = "c1", description = "Read the rules", emoji_id = nil, emoji_name = "wave" },
            { channel_id = "c2", description = "Say hi", emoji_id = "e1", emoji_name = "custom" },
        },
    }
end

describe("WelcomeScreenChannel", function()
    it("builds from a raw payload entry", function()
        local channel = WelcomeScreenChannel.from_dict({
            channel_id = "c1",
            description = "Read the rules",
            emoji_name = "wave",
        })

        assert.equals("c1", channel.channel_id)
        assert.equals("Read the rules", channel.description)
        assert.equals("wave", channel.emoji_name)
        assert.is_nil(channel.emoji_id)
    end)

    it("serializes back to a dict", function()
        local channel = WelcomeScreenChannel.new("c2", "Say hi", "e1", "custom")
        local dict = channel:to_dict()

        assert.equals("c2", dict.channel_id)
        assert.equals("Say hi", dict.description)
        assert.equals("e1", dict.emoji_id)
        assert.equals("custom", dict.emoji_name)
    end)
end)

describe("WelcomeScreen", function()
    it("creates a new welcome screen from API data", function()
        local screen = WelcomeScreen.new(screen_payload(), { id = "g1", features = {} })

        assert.equals("Welcome to the server!", screen.description)
        assert.equals(2, #screen.welcome_channels)
        assert.equals("c1", screen.welcome_channels[1].channel_id)
        assert.equals("custom", screen.welcome_channels[2].emoji_name)
        assert.equals("g1", screen.guild_id)
    end)

    it("reports enabled based on guild features", function()
        local disabled = WelcomeScreen.new(screen_payload(), { id = "g1", features = {} })
        assert.is_false(disabled:enabled())

        local enabled = WelcomeScreen.new(screen_payload(), { id = "g1", features = { "WELCOME_SCREEN_ENABLED" } })
        assert.is_true(enabled:enabled())
    end)

    it("reports disabled when guild has no features table", function()
        local screen = WelcomeScreen.new(screen_payload(), { id = "g1" })
        assert.is_false(screen:enabled())
    end)

    it("edits through the attached http client and accepts WelcomeScreenChannel instances", function()
        local http = fake_http()
        local screen = WelcomeScreen.new(screen_payload(), { id = "g1" }, http)

        screen:edit({
            description = "New welcome text",
            welcome_channels = { WelcomeScreenChannel.new("c3", "Get started", nil, "rocket") },
            enabled = true,
            reason = "refresh",
        })

        assert.equals("PATCH", http.calls[1].method)
        assert.equals("/guilds/g1/welcome-screen", http.calls[1].endpoint)
        assert.equals("New welcome text", http.calls[1].payload.description)
        assert.equals("c3", http.calls[1].payload.welcome_channels[1].channel_id)
        assert.equals(true, http.calls[1].payload.enabled)
        assert.equals("refresh", http.calls[1].opts.reason)
        assert.equals("New welcome text", screen.description)
    end)

    it("accepts plain welcome_channels tables when editing", function()
        local http = fake_http()
        local screen = WelcomeScreen.new(screen_payload(), { id = "g1" }, http)

        screen:edit({ welcome_channels = { { channel_id = "c4", description = "Plain table" } } })

        assert.equals("c4", http.calls[1].payload.welcome_channels[1].channel_id)
    end)

    it("errors on edit when no http client is attached", function()
        local screen = WelcomeScreen.new(screen_payload(), { id = "g1" })

        assert.has_error(function()
            screen:edit({ description = "x" })
        end)
    end)
end)
