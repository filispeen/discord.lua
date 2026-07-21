-- spec/models/sound_spec.lua
-- Tests for the Sound model (soundboard)

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local Sound = require("models.sound")

local function make_http()
    local calls = {}
    return {
        patch = function(_self, endpoint, payload)
            table.insert(calls, { method = "patch", endpoint = endpoint, payload = payload })
            return { sound_id = "1", name = payload.name, volume = payload.volume }
        end,
        delete = function(_self, endpoint)
            table.insert(calls, { method = "delete", endpoint = endpoint })
            return nil
        end,
    }, calls
end

describe("Sound", function()
    describe("Sound.new", function()
        it("reads id, name, volume from the payload", function()
            local sound = Sound.new({ sound_id = "1", name = "boop", volume = 0.5 })
            assert.equals("1", sound.id)
            assert.equals("boop", sound.name)
            assert.equals(0.5, sound.volume)
        end)

        it("defaults volume to 1.0", function()
            local sound = Sound.new({ sound_id = "1", name = "boop" })
            assert.equals(1.0, sound.volume)
        end)

        it("defaults available to true", function()
            local sound = Sound.new({ sound_id = "1", name = "boop" })
            assert.is_true(sound.available)
        end)

        it("builds emoji from emoji_id/emoji_name when present", function()
            local sound = Sound.new({ sound_id = "1", name = "boop", emoji_id = "9", emoji_name = nil })
            assert.equals("9", sound.emoji.id)
        end)

        it("leaves emoji nil when neither emoji field is present", function()
            local sound = Sound.new({ sound_id = "1", name = "boop" })
            assert.is_nil(sound.emoji)
        end)

        it("stores guild_id when given", function()
            local sound = Sound.new({ sound_id = "1", name = "boop" }, "guild1")
            assert.equals("guild1", sound.guild_id)
        end)
    end)

    describe("Sound:edit", function()
        it("errors for a default (non-guild) sound", function()
            local sound = Sound.new({ sound_id = "1", name = "boop" })
            assert.has_error(function()
                sound:edit({ name = "new" })
            end)
        end)

        it("errors when no http client is attached", function()
            local sound = Sound.new({ sound_id = "1", name = "boop" }, "guild1")
            assert.has_error(function()
                sound:edit({ name = "new" })
            end)
        end)

        it("PATCHes the guild sound endpoint and returns an updated Sound", function()
            local http, calls = make_http()
            local sound = Sound.new({ sound_id = "1", name = "boop", volume = 1.0 }, "guild1", http)

            local updated = sound:edit({ name = "beep" })

            assert.equals(1, #calls)
            assert.equals("patch", calls[1].method)
            assert.equals("/guilds/guild1/soundboard-sounds/1", calls[1].endpoint)
            assert.equals("beep", calls[1].payload.name)
            assert.equals("beep", updated.name)
        end)

        it("keeps the current value for fields not passed to edit", function()
            local http, calls = make_http()
            local sound = Sound.new({ sound_id = "1", name = "boop", volume = 0.7 }, "guild1", http)

            sound:edit({ name = "beep" })

            assert.equals(0.7, calls[1].payload.volume)
        end)
    end)

    describe("Sound:delete", function()
        it("errors for a default (non-guild) sound", function()
            local sound = Sound.new({ sound_id = "1", name = "boop" })
            assert.has_error(function()
                sound:delete()
            end)
        end)

        it("DELETEs the guild sound endpoint", function()
            local http, calls = make_http()
            local sound = Sound.new({ sound_id = "1", name = "boop" }, "guild1", http)

            sound:delete()

            assert.equals(1, #calls)
            assert.equals("delete", calls[1].method)
            assert.equals("/guilds/guild1/soundboard-sounds/1", calls[1].endpoint)
        end)
    end)
end)
