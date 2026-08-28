-- spec/models/activity_spec.lua
-- Tests for activity models (Game/Streaming/Activity/CustomActivity/
-- Spotify) and the create_activity factory.

require("spec_helper")

local activity = require("./models/activity")
local Activity = activity.Activity
local Game = activity.Game
local Streaming = activity.Streaming
local CustomActivity = activity.CustomActivity
local Spotify = activity.Spotify
local create_activity = activity.create_activity

describe("Game", function()
    it("defaults to the playing activity type", function()
        local game = Game.new("with the API")
        assert.equals(0, game.type)
        assert.equals("with the API", game.name)
    end)

    it("to_dict omits empty timestamps", function()
        local game = Game.new("with the API")
        local dict = game:to_dict()

        assert.equals(0, dict.type)
        assert.equals("with the API", dict.name)
        assert.is_nil(dict.timestamps.start)
        assert.is_nil(dict.timestamps["end"])
    end)

    it("to_dict includes start/end timestamps when given", function()
        local game = Game.new("with the API", { timestamps = { start = 1000, ["end"] = 2000 } })
        local dict = game:to_dict()

        assert.equals(1000, dict.timestamps.start)
        assert.equals(2000, dict.timestamps["end"])
    end)
end)

describe("Streaming", function()
    it("aliases name/details/platform like pycord", function()
        local streaming = Streaming.new({ name = "Twitch", url = "https://twitch.tv/x", state = "Some Game" })

        assert.equals("Twitch", streaming.platform)
        assert.equals("Twitch", streaming.name)
        assert.equals("Some Game", streaming.game)
        assert.equals(1, streaming.type)
    end)

    it("twitch_name strips the twitch: prefix from large_image", function()
        local streaming = Streaming.new({
            name = "Twitch",
            url = "https://twitch.tv/x",
            assets = { large_image = "twitch:some_user" },
        })

        assert.equals("some_user", streaming:twitch_name())
    end)

    it("twitch_name returns nil for a non-twitch large_image", function()
        local streaming = Streaming.new({ name = "x", url = "y", assets = { large_image = "other:thing" } })
        assert.is_nil(streaming:twitch_name())
    end)

    it("to_dict includes details only when set", function()
        local streaming = Streaming.new({ name = "Twitch", url = "https://twitch.tv/x", details = "Cool stream" })
        local dict = streaming:to_dict()

        assert.equals(1, dict.type)
        assert.equals("https://twitch.tv/x", dict.url)
        assert.equals("Cool stream", dict.details)
    end)
end)

describe("CustomActivity", function()
    it("defaults state to name", function()
        local ca = CustomActivity.new("Vibing")
        assert.equals("Vibing", ca.state)
        assert.equals(4, ca.type)
    end)

    it("swaps name for state when constructed with the literal Custom Status name", function()
        local ca = CustomActivity.new("Custom Status", { state = "Actual text" })
        assert.equals("Actual text", ca.name)
    end)

    it("accepts a plain string emoji as the emoji name", function()
        local ca = CustomActivity.new("Vibing", { emoji = "🎧" })
        assert.equals("🎧", ca.emoji.name)
    end)

    it("accepts a raw emoji table unchanged", function()
        local ca = CustomActivity.new("Vibing", { emoji = { id = "1", name = "pog" } })
        assert.equals("1", ca.emoji.id)
        assert.equals("pog", ca.emoji.name)
    end)

    it("errors on an unsupported emoji type", function()
        assert.has_error(function()
            CustomActivity.new("Vibing", { emoji = 5 })
        end)
    end)

    it("to_dict uses the Custom Status name/state form when name equals state", function()
        local ca = CustomActivity.new("Vibing")
        local dict = ca:to_dict()

        assert.equals("Custom Status", dict.name)
        assert.equals("Vibing", dict.state)
    end)

    it("to_dict keeps the explicit name when it differs from state", function()
        local ca = CustomActivity.new("Vibing", { state = "Something else" })
        local dict = ca:to_dict()

        assert.equals("Vibing", dict.name)
        assert.is_nil(dict.state)
    end)
end)

describe("Activity", function()
    it("defaults type to -1 and fills the Custom Status name for custom activities with no name", function()
        local a = Activity.new({ type = 4 })
        assert.equals("Custom Status", a.name)
    end)

    it("to_dict omits nil/empty fields", function()
        local a = Activity.new({ type = 0, name = "Game" })
        local dict = a:to_dict()

        assert.equals(0, dict.type)
        assert.equals("Game", dict.name)
        assert.is_nil(dict.state)
        assert.is_nil(dict.timestamps)
    end)

    it("large_image_url/small_image_url require application_id", function()
        local a = Activity.new({ type = 0, assets = { large_image = "abc" } })
        assert.is_nil(a:large_image_url())
    end)

    it("large_image_url builds the app-assets CDN URL", function()
        local a = Activity.new({ type = 0, application_id = "999", assets = { large_image = "abc" } })
        assert.equals("https://cdn.discordapp.com/app-assets/999/abc.png", a:large_image_url())
    end)

    it("large_image_text/small_image_text read straight off assets", function()
        local a = Activity.new({ type = 0, assets = { large_text = "Large", small_text = "Small" } })
        assert.equals("Large", a:large_image_text())
        assert.equals("Small", a:small_image_text())
    end)
end)

describe("Spotify", function()
    local function make_spotify()
        return Spotify.new({
            state = "Artist One; Artist Two",
            details = "Song Title",
            timestamps = { start = 1000, ["end"] = 5000 },
            assets = { large_text = "Album Name", large_image = "spotify:abc123" },
            party = { id = "party1" },
            sync_id = "track1",
            session_id = "session1",
        })
    end

    it("exposes title/artist/artists", function()
        local spotify = make_spotify()
        assert.equals("Song Title", spotify:title())
        assert.equals("Artist One; Artist Two", spotify:artist())
        assert.same({ "Artist One", "Artist Two" }, spotify:artists())
    end)

    it("exposes album and album_cover_url", function()
        local spotify = make_spotify()
        assert.equals("Album Name", spotify:album())
        assert.equals("https://i.scdn.co/image/abc123", spotify:album_cover_url())
    end)

    it("album_cover_url returns empty string without a spotify: prefix", function()
        local spotify = Spotify.new({ assets = { large_image = "other:abc123" } })
        assert.equals("", spotify:album_cover_url())
    end)

    it("exposes track_id/track_url", function()
        local spotify = make_spotify()
        assert.equals("track1", spotify:track_id())
        assert.equals("https://open.spotify.com/track/track1", spotify:track_url())
    end)

    it("exposes start_time/end_time/duration_ms", function()
        local spotify = make_spotify()
        assert.equals(1000, spotify:start_time())
        assert.equals(5000, spotify:end_time())
        assert.equals(4000, spotify:duration_ms())
    end)

    it("exposes party_id and colour", function()
        local spotify = make_spotify()
        assert.equals("party1", spotify:party_id())
        assert.equals(0x1DB954, spotify:colour())
        assert.equals(0x1DB954, spotify:color())
    end)

    it("to_dict round-trips the raw fields", function()
        local spotify = make_spotify()
        local dict = spotify:to_dict()

        assert.equals("Spotify", dict.name)
        assert.equals(48, dict.flags)
        assert.equals("track1", dict.sync_id)
        assert.equals("session1", dict.session_id)
    end)
end)

local function is_instance(obj, ClassTable)
    local mt = getmetatable(obj)
    return mt == ClassTable or mt.__index == ClassTable
end

describe("create_activity", function()
    it("returns nil for nil input", function()
        assert.is_nil(create_activity(nil))
    end)

    it("builds a Game for a plain playing activity", function()
        local result = create_activity({ type = 0, name = "with the API" })
        assert.is_true(is_instance(result, Game))
        assert.equals("with the API", result.name)
    end)

    it("builds an Activity for a playing activity with application_id set", function()
        local result = create_activity({ type = 0, name = "Rich", application_id = "123" })
        assert.is_true(is_instance(result, Activity))
    end)

    it("builds a CustomActivity for a custom activity with a name", function()
        local result = create_activity({ type = 4, name = "Vibing", state = "Vibing" })
        assert.is_true(is_instance(result, CustomActivity))
        assert.equals("Vibing", result.name)
    end)

    it("builds a Streaming for a streaming activity with a url", function()
        local result = create_activity({ type = 1, name = "Twitch", url = "https://twitch.tv/x" })
        assert.is_true(is_instance(result, Streaming))
    end)

    it("builds a Spotify for a listening activity with sync_id and session_id", function()
        local result = create_activity({ type = 2, sync_id = "a", session_id = "b" })
        assert.is_true(is_instance(result, Spotify))
    end)

    it("falls back to Activity for a listening activity without spotify fields", function()
        local result = create_activity({ type = 2, name = "some podcast" })
        assert.is_true(is_instance(result, Activity))
    end)
end)
