-- spec/models/thread_spec.lua
-- Tests for thread model

require("spec_helper")

local Thread = require("./models/thread")

local function fake_http()
    local calls = {}
    return {
        calls = calls,
        get = function(_self, endpoint)
            table.insert(calls, { method = "GET", endpoint = endpoint })
            return { { user_id = "u1" } }
        end,
        patch = function(_self, endpoint, payload)
            table.insert(calls, { method = "PATCH", endpoint = endpoint, payload = payload })
            return {
                id = "1",
                type = 14,
                name = payload.name or "thread",
                parent_id = "c1",
                thread_metadata = {
                    archived = payload.archived or false,
                    locked = payload.locked or false,
                    auto_archive_duration = payload.auto_archive_duration or 1440,
                    invitable = true,
                },
            }
        end,
        put = function(_self, endpoint)
            table.insert(calls, { method = "PUT", endpoint = endpoint })
            return true
        end,
        delete = function(_self, endpoint)
            table.insert(calls, { method = "DELETE", endpoint = endpoint })
            return true
        end,
    }
end

local function thread_payload()
    return {
        id = "1",
        type = 14,
        name = "help-thread",
        parent_id = "c1",
        guild_id = "g1",
        owner_id = "u1",
        last_message_id = "m5",
        rate_limit_per_user = 5,
        message_count = 3,
        member_count = 2,
        thread_metadata = {
            archived = false,
            auto_archive_duration = 1440,
            archive_timestamp = "2026-01-01T00:00:00Z",
            create_timestamp = "2025-12-01T00:00:00Z",
            locked = false,
            invitable = true,
        },
    }
end

describe("Thread", function()
    it("creates a new thread from API data", function()
        local thread = Thread.new(thread_payload())

        assert.equals("1", thread.id)
        assert.equals("help-thread", thread.name)
        assert.equals("c1", thread.parent_id)
        assert.equals("u1", thread.owner_id)
        assert.equals(5, thread.slowmode_delay)
        assert.equals(3, thread.message_count)
        assert.equals(2, thread.member_count)
        assert.is_false(thread.archived)
        assert.is_false(thread.locked)
        assert.is_true(thread.invitable)
        assert.equals(1440, thread.auto_archive_duration)
    end)

    it("defaults invitable to true when missing from metadata", function()
        local data = thread_payload()
        data.thread_metadata.invitable = nil
        local thread = Thread.new(data)

        assert.is_true(thread.invitable)
    end)

    it("identifies itself as a thread by type", function()
        local thread = Thread.new(thread_payload())
        assert.is_true(thread:is_thread())
    end)

    it("edits the thread through the attached http client", function()
        local http = fake_http()
        local thread = Thread.new(thread_payload(), nil, http)

        thread:edit({ name = "renamed", slowmode_delay = 10 })

        assert.equals("PATCH", http.calls[1].method)
        assert.equals("/channels/1", http.calls[1].endpoint)
        assert.equals("renamed", http.calls[1].payload.name)
        assert.equals(10, http.calls[1].payload.rate_limit_per_user)
        assert.equals("renamed", thread.name)
    end)

    it("archives the thread as a shorthand for edit", function()
        local http = fake_http()
        local thread = Thread.new(thread_payload(), nil, http)

        thread:archive(true)

        assert.is_true(http.calls[1].payload.archived)
        assert.is_true(http.calls[1].payload.locked)
    end)

    it("unarchives the thread as a shorthand for edit", function()
        local http = fake_http()
        local thread = Thread.new(thread_payload(), nil, http)

        thread:unarchive()

        assert.is_false(http.calls[1].payload.archived)
    end)

    it("joins the thread through the attached http client", function()
        local http = fake_http()
        local thread = Thread.new(thread_payload(), nil, http)

        thread:join()

        assert.equals("PUT", http.calls[1].method)
        assert.equals("/channels/1/thread-members/@me", http.calls[1].endpoint)
    end)

    it("leaves the thread through the attached http client", function()
        local http = fake_http()
        local thread = Thread.new(thread_payload(), nil, http)

        thread:leave()

        assert.equals("DELETE", http.calls[1].method)
        assert.equals("/channels/1/thread-members/@me", http.calls[1].endpoint)
    end)

    it("adds a user to the thread", function()
        local http = fake_http()
        local thread = Thread.new(thread_payload(), nil, http)

        thread:add_user("u2")

        assert.equals("PUT", http.calls[1].method)
        assert.equals("/channels/1/thread-members/u2", http.calls[1].endpoint)
    end)

    it("removes a user from the thread", function()
        local http = fake_http()
        local thread = Thread.new(thread_payload(), nil, http)

        thread:remove_user("u2")

        assert.equals("DELETE", http.calls[1].method)
        assert.equals("/channels/1/thread-members/u2", http.calls[1].endpoint)
    end)

    it("fetches thread members", function()
        local http = fake_http()
        local thread = Thread.new(thread_payload(), nil, http)

        local members = thread:fetch_members()

        assert.equals("GET", http.calls[1].method)
        assert.equals("/channels/1/thread-members", http.calls[1].endpoint)
        assert.equals("u1", members[1].user_id)
    end)

    it("deletes the thread", function()
        local http = fake_http()
        local thread = Thread.new(thread_payload(), nil, http)

        thread:delete()

        assert.equals("DELETE", http.calls[1].method)
        assert.equals("/channels/1", http.calls[1].endpoint)
    end)

    it("errors on edit when no http client is attached", function()
        local thread = Thread.new(thread_payload())

        assert.has_error(function()
            thread:edit({ name = "x" })
        end)
    end)
end)
