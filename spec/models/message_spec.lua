-- spec/models/message_spec.lua
-- Tests for message model

-- Setup package path to find lib modules
require("spec_helper")

local Message = require("./models/message")

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
        put = function(_self, endpoint, payload)
            table.insert(calls, { method = "PUT", endpoint = endpoint, payload = payload })
            return true
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

    it("wraps raw reaction payloads into Reaction instances", function()
        local message = Message.new({
            id = "1",
            channel_id = "c1",
            reactions = {
                { emoji = { name = "🔥" }, count = 3, me = true },
                { emoji = { id = "9", name = "pog" }, count = 1 },
            },
        })

        assert.equals(2, #message.reactions)
        assert.equals("🔥", message.reactions[1].emoji_key)
        assert.equals(3, message.reactions[1].count)
        assert.is_true(message.reactions[1].me)
        assert.equals("pog:9", message.reactions[2].emoji_key)
    end)

    it("adds a unicode reaction through the attached http client", function()
        local http = fake_http()
        local message = Message.new({ id = "1", channel_id = "c1" }, http)

        message:add_reaction("🔥")

        assert.equals(1, #http.calls)
        assert.equals("PUT", http.calls[1].method)
        assert.equals("/channels/c1/messages/1/reactions/%F0%9F%94%A5/@me", http.calls[1].endpoint)
    end)

    it("adds a custom emoji reaction using name:id format", function()
        local http = fake_http()
        local message = Message.new({ id = "1", channel_id = "c1" }, http)

        message:add_reaction({ name = "pog", id = "9" })

        assert.equals("/channels/c1/messages/1/reactions/pog:9/@me", http.calls[1].endpoint)
    end)

    it("errors on add_reaction when no http client is attached", function()
        local message = Message.new({ id = "1", channel_id = "c1" })

        assert.has_error(function()
            message:add_reaction("🔥")
        end)
    end)

    it("removes the bot's own reaction by default", function()
        local http = fake_http()
        local message = Message.new({ id = "1", channel_id = "c1" }, http)

        message:remove_reaction("🔥")

        assert.equals("DELETE", http.calls[1].method)
        assert.equals("/channels/c1/messages/1/reactions/%F0%9F%94%A5/@me", http.calls[1].endpoint)
    end)

    it("removes another user's reaction when given a user id", function()
        local http = fake_http()
        local message = Message.new({ id = "1", channel_id = "c1" }, http)

        message:remove_reaction("🔥", "u2")

        assert.equals("/channels/c1/messages/1/reactions/%F0%9F%94%A5/u2", http.calls[1].endpoint)
    end)

    it("clears a single emoji's reactions", function()
        local http = fake_http()
        local message = Message.new({ id = "1", channel_id = "c1" }, http)

        message:clear_reaction("🔥")

        assert.equals("DELETE", http.calls[1].method)
        assert.equals("/channels/c1/messages/1/reactions/%F0%9F%94%A5", http.calls[1].endpoint)
    end)

    it("clears all reactions", function()
        local http = fake_http()
        local message = Message.new({ id = "1", channel_id = "c1" }, http)

        message:clear_reactions()

        assert.equals("DELETE", http.calls[1].method)
        assert.equals("/channels/c1/messages/1/reactions", http.calls[1].endpoint)
    end)

    it("applies a gateway reaction add to a new emoji", function()
        local message = Message.new({ id = "1", channel_id = "c1" })

        local reaction = message:_add_reaction({ emoji = { name = "🔥" }, user_id = "u1" }, "bot_id")

        assert.equals(1, #message.reactions)
        assert.equals(1, reaction.count)
        assert.is_false(reaction.me)
    end)

    it("applies a gateway reaction add as its own reaction when user matches", function()
        local message = Message.new({ id = "1", channel_id = "c1" })

        local reaction = message:_add_reaction({ emoji = { name = "🔥" }, user_id = "bot_id" }, "bot_id")

        assert.is_true(reaction.me)
    end)

    it("increments an existing reaction's count on gateway add", function()
        local message = Message.new({
            id = "1",
            channel_id = "c1",
            reactions = { { emoji = { name = "🔥" }, count = 1 } },
        })

        local reaction = message:_add_reaction({ emoji = { name = "🔥" }, user_id = "u2" }, "bot_id")

        assert.equals(1, #message.reactions)
        assert.equals(2, reaction.count)
    end)

    it("decrements and drops a reaction once its count reaches 0 on gateway remove", function()
        local message = Message.new({
            id = "1",
            channel_id = "c1",
            reactions = { { emoji = { name = "🔥" }, count = 1, me = true } },
        })

        local reaction = message:_remove_reaction({ emoji = { name = "🔥" }, user_id = "bot_id" }, "bot_id")

        assert.equals(0, #message.reactions)
        assert.equals(0, reaction.count)
    end)

    it("decrements without dropping when other reactions remain", function()
        local message = Message.new({
            id = "1",
            channel_id = "c1",
            reactions = { { emoji = { name = "🔥" }, count = 2 } },
        })

        message:_remove_reaction({ emoji = { name = "🔥" }, user_id = "u2" }, "bot_id")

        assert.equals(1, #message.reactions)
        assert.equals(1, message.reactions[1].count)
    end)

    it("clears a single emoji locally via gateway remove_emoji", function()
        local message = Message.new({
            id = "1",
            channel_id = "c1",
            reactions = {
                { emoji = { name = "🔥" }, count = 2 },
                { emoji = { name = "🎉" }, count = 1 },
            },
        })

        local removed = message:_clear_emoji({ name = "🔥" })

        assert.equals(1, #message.reactions)
        assert.equals("🎉", message.reactions[1].emoji_key)
        assert.equals("🔥", removed.emoji_key)
    end)

    it("clears every reaction locally via gateway remove_all", function()
        local message = Message.new({
            id = "1",
            channel_id = "c1",
            reactions = {
                { emoji = { name = "🔥" }, count = 2 },
                { emoji = { name = "🎉" }, count = 1 },
            },
        })

        local old = message:_clear_reactions()

        assert.equals(0, #message.reactions)
        assert.equals(2, #old)
    end)

    it("creates a thread from the message through the attached http client", function()
        local http = fake_http()
        http.post = function(_self, endpoint, payload)
            table.insert(http.calls, { method = "POST", endpoint = endpoint, payload = payload })
            return { id = "t1", type = 11, name = payload.name, parent_id = "c1" }
        end
        local message = Message.new({ id = "1", channel_id = "c1" }, http)

        local thread = message:create_thread({ name = "discussion" })

        assert.equals("/channels/c1/messages/1/threads", http.calls[1].endpoint)
        assert.equals("discussion", http.calls[1].payload.name)
        assert.equals("t1", thread.id)
    end)

    it("errors on create_thread when no http client is attached", function()
        local message = Message.new({ id = "1", channel_id = "c1" })

        assert.has_error(function()
            message:create_thread({ name = "discussion" })
        end)
    end)

    it("errors on create_thread when no name is given", function()
        local http = fake_http()
        local message = Message.new({ id = "1", channel_id = "c1" }, http)

        assert.has_error(function()
            message:create_thread()
        end)
    end)

    it("parses a poll payload into a Poll instance", function()
        local message = Message.new({
            id = "1",
            channel_id = "c1",
            poll = {
                question = { text = "Favorite color?" },
                answers = { { poll_media = { text = "Red" }, answer_id = 1 } },
                duration = 24,
                allow_multiselect = false,
                layout_type = 1,
            },
        })

        assert.is_not_nil(message.poll)
        assert.equals("Favorite color?", message.poll.question.text)
        assert.equals(message, message.poll.message)
    end)

    it("leaves poll nil when the message has none", function()
        local message = Message.new({ id = "1", channel_id = "c1" })
        assert.is_nil(message.poll)
    end)

    it("ends the poll through the attached http client", function()
        local http = fake_http()
        http.post = function(_self, endpoint)
            table.insert(http.calls, { method = "POST", endpoint = endpoint })
            return { id = "1" }
        end
        local message = Message.new({
            id = "1",
            channel_id = "c1",
            poll = { question = { text = "Q" }, answers = {} },
        }, http)

        message:end_poll()

        assert.equals("/channels/c1/polls/1/expire", http.calls[1].endpoint)
    end)

    it("errors on end_poll when the message has no poll", function()
        local http = fake_http()
        local message = Message.new({ id = "1", channel_id = "c1" }, http)

        assert.has_error(function()
            message:end_poll()
        end)
    end)

    it("gets poll answer voters with pagination params", function()
        local http = fake_http()
        http.get = function(_self, endpoint)
            table.insert(http.calls, { method = "GET", endpoint = endpoint })
            return { { id = "u1" } }
        end
        local message = Message.new({
            id = "1",
            channel_id = "c1",
            poll = { question = { text = "Q" }, answers = {} },
        }, http)

        message:get_poll_answer_voters(1, { limit = 25, after = "u0" })

        assert.equals("/channels/c1/polls/1/answers/1?limit=25&after=u0", http.calls[1].endpoint)
    end)

    it("gets poll answer voters without pagination params", function()
        local http = fake_http()
        http.get = function(_self, endpoint)
            table.insert(http.calls, { method = "GET", endpoint = endpoint })
            return {}
        end
        local message = Message.new({
            id = "1",
            channel_id = "c1",
            poll = { question = { text = "Q" }, answers = {} },
        }, http)

        message:get_poll_answer_voters(1)

        assert.equals("/channels/c1/polls/1/answers/1", http.calls[1].endpoint)
    end)

    it("uploads files when replying or editing", function()
        local File = require("./models/file")
        local calls = {}
        local http = {
            post_multipart = function(_self, endpoint, payload, files)
                calls[#calls + 1] = { method = "POST", endpoint = endpoint, payload = payload, files = files }
            end,
            patch_multipart = function(_self, endpoint, payload, files)
                calls[#calls + 1] = { method = "PATCH", endpoint = endpoint, payload = payload, files = files }
            end,
        }
        local message = Message.new({ id = "1", channel_id = "c1" }, http)
        local file = File.from_bytes("hello", "note.txt")

        message:reply("reply", { files = { file } })
        message:edit("edit", { files = { file }, attachments = {} })

        assert.equals("POST", calls[1].method)
        assert.equals("/channels/c1/messages", calls[1].endpoint)
        assert.equals("note.txt", calls[1].payload.attachments[1].filename)
        assert.equals("PATCH", calls[2].method)
        assert.equals("/channels/c1/messages/1", calls[2].endpoint)
        assert.same({}, calls[2].payload.attachments)
    end)
end)
