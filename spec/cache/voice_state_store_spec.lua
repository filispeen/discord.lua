-- spec/cache/voice_state_store_spec.lua
-- Tests for the voice state cache, built from VOICE_STATE_UPDATE payloads.

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local VoiceStateStore = require("cache.voice_state_store")

describe("VoiceStateStore", function()
    it("returns nil for a user never seen in voice", function()
        local store = VoiceStateStore.new()
        assert.is_nil(store:get("guild1", "user1"))
        assert.is_nil(store:get_channel_id("guild1", "user1"))
    end)

    it("stores a voice state when the user joins a channel", function()
        local store = VoiceStateStore.new()
        store:update({
            guild_id = "guild1",
            user_id = "user1",
            channel_id = "channel1",
            session_id = "session1",
        })

        local state = store:get("guild1", "user1")
        assert.is_not_nil(state)
        assert.equals("channel1", state.channel_id)
        assert.equals("session1", state.session_id)
        assert.equals("channel1", store:get_channel_id("guild1", "user1"))
    end)

    it("updates the channel when the user moves channels", function()
        local store = VoiceStateStore.new()
        store:update({ guild_id = "guild1", user_id = "user1", channel_id = "channel1" })
        store:update({ guild_id = "guild1", user_id = "user1", channel_id = "channel2" })

        assert.equals("channel2", store:get_channel_id("guild1", "user1"))
    end)

    it("removes the state when channel_id is Lua nil (field omitted)", function()
        local store = VoiceStateStore.new()
        store:update({ guild_id = "guild1", user_id = "user1", channel_id = "channel1" })
        store:update({ guild_id = "guild1", user_id = "user1", channel_id = nil })

        assert.is_nil(store:get("guild1", "user1"))
    end)

    it("removes the state when channel_id is the json.null sentinel", function()
        package.loaded["json"] = { null = setmetatable({}, {}) }
        package.loaded["cache.voice_state_store"] = nil
        local FreshStore = require("cache.voice_state_store")

        local store = FreshStore.new()
        store:update({ guild_id = "guild1", user_id = "user1", channel_id = "channel1" })
        store:update({ guild_id = "guild1", user_id = "user1", channel_id = package.loaded["json"].null })

        assert.is_nil(store:get("guild1", "user1"))

        package.loaded["json"] = nil
        package.loaded["cache.voice_state_store"] = nil
    end)

    it("keeps voice states separate per guild for the same user", function()
        local store = VoiceStateStore.new()
        store:update({ guild_id = "guild1", user_id = "user1", channel_id = "channel1" })
        store:update({ guild_id = "guild2", user_id = "user1", channel_id = "channel9" })

        assert.equals("channel1", store:get_channel_id("guild1", "user1"))
        assert.equals("channel9", store:get_channel_id("guild2", "user1"))
    end)

    it("ignores an update payload missing guild_id or user_id", function()
        local store = VoiceStateStore.new()
        store:update({ user_id = "user1", channel_id = "channel1" })
        store:update({ guild_id = "guild1", channel_id = "channel1" })
        store:update(nil)

        assert.is_nil(store:get("guild1", "user1"))
    end)
end)
