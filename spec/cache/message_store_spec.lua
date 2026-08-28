require("spec_helper")

local MessageStore = require("./cache/message_store")

describe("MessageStore", function()
    it("stores messages by channel and message id", function()
        local store = MessageStore.new()
        local message = { channel_id = "channel1", id = "message1" }
        store:put(message)

        assert.equals(message, store:get("channel1", "message1"))
    end)

    it("keeps equal message ids from separate channels", function()
        local store = MessageStore.new()
        local first = { channel_id = "channel1", id = "message1" }
        local second = { channel_id = "channel2", id = "message1" }
        store:put(first)
        store:put(second)

        assert.equals(first, store:get("channel1", "message1"))
        assert.equals(second, store:get("channel2", "message1"))
    end)

    it("removes one or many messages", function()
        local store = MessageStore.new()
        store:put({ channel_id = "channel1", id = "message1" })
        store:put({ channel_id = "channel1", id = "message2" })
        store:put({ channel_id = "channel1", id = "message3" })

        store:remove("channel1", "message1")
        store:remove_many("channel1", { "message2", "message3" })

        assert.is_nil(store:get("channel1", "message1"))
        assert.is_nil(store:get("channel1", "message2"))
        assert.is_nil(store:get("channel1", "message3"))
    end)

    it("is bounded", function()
        local store = MessageStore.new(1)
        store:put({ channel_id = "channel1", id = "message1" })
        store:put({ channel_id = "channel1", id = "message2" })

        assert.is_nil(store:get("channel1", "message1"))
        assert.is_not_nil(store:get("channel1", "message2"))
    end)
end)
