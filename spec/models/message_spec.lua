-- spec/models/message_spec.lua
-- Tests for message model

-- Setup package path to find lib modules
package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local Message = require("models.message")

local function fake_http()
    local calls = {}
    return {
        calls = calls,
        post = function(_self, endpoint, payload)
            table.insert(calls, { method = "POST", endpoint = endpoint, payload = payload })
            return { id = "new_message" }
        end,
        patch = function(_self, endpoint, payload)
            table.insert(calls, { method = "PATCH", endpoint = endpoint, payload = payload })
            return { id = "edited_message" }
        end,
        delete = function(_self, endpoint)
            table.insert(calls, { method = "DELETE", endpoint = endpoint })
            return true
        end,
    }
end

describe("Message", function()
    it("creates a new message", function()
        local message = Message.new({ id = "1", content = "hello", channel_id = "c1" })

        assert.equals("1", message.id)
        assert.equals("hello", message.content)
        assert.equals("c1", message.channel_id)
    end)

    it("defaults content to an empty string", function()
        local message = Message.new({ id = "1", channel_id = "c1" })

        assert.equals("", message.content)
    end)

    it("checks if a user is mentioned", function()
        local message = Message.new({
            id = "1",
            channel_id = "c1",
            mentions = { { id = "u1" }, { id = "u2" } },
        })

        assert.is_true(message:mentions_user("u1"))
        assert.is_false(message:mentions_user("u3"))
    end)

    it("checks if a role is mentioned", function()
        local message = Message.new({
            id = "1",
            channel_id = "c1",
            mention_roles = { "r1", "r2" },
        })

        assert.is_true(message:mentions_role("r1"))
        assert.is_false(message:mentions_role("r3"))
    end)

    it("sends a reply through the attached http client", function()
        local http = fake_http()
        local message = Message.new({ id = "1", channel_id = "c1" }, http)

        message:reply("Pong!")

        assert.equals(1, #http.calls)
        assert.equals("POST", http.calls[1].method)
        assert.equals("/channels/c1/messages", http.calls[1].endpoint)
        assert.equals("Pong!", http.calls[1].payload.content)
    end)

    it("errors on reply when no http client is attached", function()
        local message = Message.new({ id = "1", channel_id = "c1" })

        assert.has_error(function()
            message:reply("Pong!")
        end)
    end)

    it("edits the message through the attached http client", function()
        local http = fake_http()
        local message = Message.new({ id = "1", channel_id = "c1" }, http)

        message:edit("Updated")

        assert.equals(1, #http.calls)
        assert.equals("PATCH", http.calls[1].method)
        assert.equals("/channels/c1/messages/1", http.calls[1].endpoint)
        assert.equals("Updated", http.calls[1].payload.content)
    end)

    it("deletes the message through the attached http client", function()
        local http = fake_http()
        local message = Message.new({ id = "1", channel_id = "c1" }, http)

        message:delete()

        assert.equals(1, #http.calls)
        assert.equals("DELETE", http.calls[1].method)
        assert.equals("/channels/c1/messages/1", http.calls[1].endpoint)
    end)
end)
