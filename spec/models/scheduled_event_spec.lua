-- spec/models/scheduled_event_spec.lua
-- Tests for scheduled event model

require("spec_helper")

local ScheduledEvent = require("./models/scheduled_event")

local function fake_http()
    local calls = {}
    return {
        calls = calls,
        get = function(_self, endpoint)
            table.insert(calls, { method = "GET", endpoint = endpoint })
            return { { id = "u1" } }
        end,
        patch = function(_self, endpoint, payload, opts)
            table.insert(calls, { method = "PATCH", endpoint = endpoint, payload = payload, opts = opts })
            return {
                id = "1",
                guild_id = "g1",
                name = payload.name or "Community night",
                status = payload.status or 1,
                scheduled_start_time = "2026-01-01T00:00:00Z",
            }
        end,
        delete = function(_self, endpoint)
            table.insert(calls, { method = "DELETE", endpoint = endpoint })
            return true
        end,
    }
end

local function event_payload()
    return {
        id = "1",
        guild_id = "g1",
        name = "Community night",
        description = "Fun times",
        scheduled_start_time = "2026-01-01T00:00:00Z",
        scheduled_end_time = "2026-01-01T02:00:00Z",
        status = 1,
        privacy_level = 2,
        user_count = 5,
        creator_id = "u1",
        entity_type = 2,
        channel_id = "c1",
    }
end

describe("ScheduledEvent", function()
    it("creates a new scheduled event from API data", function()
        local event = ScheduledEvent.new(event_payload())

        assert.equals("1", event.id)
        assert.equals("g1", event.guild_id)
        assert.equals("Community night", event.name)
        assert.equals(1, event.status)
        assert.equals(5, event.subscriber_count)
        assert.equals("c1", event.channel_id)
        assert.is_nil(event.location)
    end)

    it("reads location from entity_metadata for external events", function()
        local data = event_payload()
        data.entity_type = 3
        data.channel_id = nil
        data.entity_metadata = { location = "The Park" }

        local event = ScheduledEvent.new(data)
        assert.equals("The Park", event.location)
    end)

    it("falls back to guild.id when the payload has no guild_id", function()
        local data = event_payload()
        data.guild_id = nil
        local guild = { id = "g2" }

        local event = ScheduledEvent.new(data, guild)
        assert.equals("g2", event.guild_id)
    end)

    it("edits the event through the attached http client", function()
        local http = fake_http()
        local event = ScheduledEvent.new(event_payload(), nil, http)

        event:edit({ name = "Renamed night" })

        assert.equals("PATCH", http.calls[1].method)
        assert.equals("/guilds/g1/scheduled-events/1", http.calls[1].endpoint)
        assert.equals("Renamed night", http.calls[1].payload.name)
        assert.equals("Renamed night", event.name)
    end)

    it("sets entity_type external and metadata when editing with a location", function()
        local http = fake_http()
        local event = ScheduledEvent.new(event_payload(), nil, http)

        event:edit({ location = "The Park" })

        assert.equals(3, http.calls[1].payload.entity_type)
        assert.equals("The Park", http.calls[1].payload.entity_metadata.location)
        assert.is_nil(http.calls[1].payload.channel_id)
    end)

    it("starts the event as a shorthand for edit", function()
        local http = fake_http()
        local event = ScheduledEvent.new(event_payload(), nil, http)

        event:start()

        assert.equals(2, http.calls[1].payload.status)
    end)

    it("completes the event as a shorthand for edit", function()
        local http = fake_http()
        local event = ScheduledEvent.new(event_payload(), nil, http)

        event:complete()

        assert.equals(3, http.calls[1].payload.status)
    end)

    it("cancels the event as a shorthand for edit", function()
        local http = fake_http()
        local event = ScheduledEvent.new(event_payload(), nil, http)

        event:cancel()

        assert.equals(4, http.calls[1].payload.status)
    end)

    it("deletes the event through the attached http client", function()
        local http = fake_http()
        local event = ScheduledEvent.new(event_payload(), nil, http)

        event:delete()

        assert.equals("DELETE", http.calls[1].method)
        assert.equals("/guilds/g1/scheduled-events/1", http.calls[1].endpoint)
    end)

    it("fetches subscribers with default pagination", function()
        local http = fake_http()
        local event = ScheduledEvent.new(event_payload(), nil, http)

        local subscribers = event:fetch_subscribers()

        assert.equals("GET", http.calls[1].method)
        assert.equals("/guilds/g1/scheduled-events/1/users?limit=100&with_member=0", http.calls[1].endpoint)
        assert.equals("u1", subscribers[1].id)
    end)

    it("fetches subscribers with custom pagination", function()
        local http = fake_http()
        local event = ScheduledEvent.new(event_payload(), nil, http)

        event:fetch_subscribers({ limit = 10, with_member = true, before = "u5", after = "u1" })

        assert.equals(
            "/guilds/g1/scheduled-events/1/users?limit=10&with_member=1&before=u5&after=u1",
            http.calls[1].endpoint
        )
    end)

    it("errors on edit when no http client is attached", function()
        local event = ScheduledEvent.new(event_payload())

        assert.has_error(function()
            event:edit({ name = "x" })
        end)
    end)
end)
