-- spec/models/guild_spec.lua
-- Tests for the Guild model, focused on soundboard integration

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local Guild = require("models.guild")

local function make_http(get_response, post_response)
    local calls = {}
    return {
        get = function(_self, endpoint)
            table.insert(calls, { method = "get", endpoint = endpoint })
            return get_response
        end,
        post = function(_self, endpoint, payload)
            table.insert(calls, { method = "post", endpoint = endpoint, payload = payload })
            return post_response
        end,
    }, calls
end

describe("Guild", function()
    describe("Guild.new", function()
        it("reads core fields from the payload", function()
            local guild = Guild.new({ id = "1", name = "Test Guild" })
            assert.equals("1", guild.id)
            assert.equals("Test Guild", guild.name)
        end)

        it("stores an optional http client", function()
            local http = {}
            local guild = Guild.new({ id = "1", name = "Test" }, http)
            assert.equals(http, guild.http)
        end)
    end)

    describe("Guild:fetch_sounds", function()
        it("errors when no http client is attached", function()
            local guild = Guild.new({ id = "1", name = "Test" })
            assert.has_error(function()
                guild:fetch_sounds()
            end)
        end)

        it("GETs the guild soundboard-sounds endpoint and returns Sound instances", function()
            local http, calls = make_http({ items = {
                { sound_id = "1", name = "boop" },
                { sound_id = "2", name = "beep" },
            } })
            local guild = Guild.new({ id = "guild1", name = "Test" }, http)

            local sounds = guild:fetch_sounds()

            assert.equals(1, #calls)
            assert.equals("/guilds/guild1/soundboard-sounds", calls[1].endpoint)
            assert.equals(2, #sounds)
            assert.equals("boop", sounds[1].name)
            assert.equals("guild1", sounds[1].guild_id)
        end)

        it("handles a bare array response with no items wrapper", function()
            local http = make_http({ { sound_id = "1", name = "boop" } })
            local guild = Guild.new({ id = "guild1", name = "Test" }, http)

            local sounds = guild:fetch_sounds()

            assert.equals(1, #sounds)
        end)
    end)

    describe("Guild:create_sound", function()
        it("errors when no http client is attached", function()
            local guild = Guild.new({ id = "1", name = "Test" })
            assert.has_error(function()
                guild:create_sound({ name = "boop", sound = "data:audio/mpeg;base64,AA" })
            end)
        end)

        it("requires opts.name", function()
            local http = make_http()
            local guild = Guild.new({ id = "1", name = "Test" }, http)
            assert.has_error(function()
                guild:create_sound({ sound = "data:audio/mpeg;base64,AA" })
            end)
        end)

        it("requires opts.sound", function()
            local http = make_http()
            local guild = Guild.new({ id = "1", name = "Test" }, http)
            assert.has_error(function()
                guild:create_sound({ name = "boop" })
            end)
        end)

        it("POSTs the guild soundboard-sounds endpoint and returns a Sound", function()
            local http, calls = make_http(nil, { sound_id = "1", name = "boop", volume = 1.0 })
            local guild = Guild.new({ id = "guild1", name = "Test" }, http)

            local sound = guild:create_sound({ name = "boop", sound = "data:audio/mpeg;base64,AA" })

            assert.equals(1, #calls)
            assert.equals("/guilds/guild1/soundboard-sounds", calls[1].endpoint)
            assert.equals("boop", calls[1].payload.name)
            assert.equals("boop", sound.name)
            assert.equals("guild1", sound.guild_id)
        end)

        it("defaults volume to 1.0 when not given", function()
            local http, calls = make_http(nil, { sound_id = "1", name = "boop" })
            local guild = Guild.new({ id = "guild1", name = "Test" }, http)

            guild:create_sound({ name = "boop", sound = "data:audio/mpeg;base64,AA" })

            assert.equals(1.0, calls[1].payload.volume)
        end)
    end)
end)
