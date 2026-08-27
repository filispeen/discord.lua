-- spec/models/stage_instance_spec.lua
-- Tests for the StageInstance model

require("spec_helper")

local StageInstance = require("./models/stage_instance")

local function instance_payload()
    return {
        id = "s1",
        channel_id = "c1",
        guild_id = "g1",
        topic = "General",
        privacy_level = 2,
        discoverable_disabled = false,
        guild_scheduled_event_id = "e1",
    }
end

local function fake_http()
    local calls = {}
    return {
        calls = calls,
        patch = function(_self, endpoint, payload, opts)
            table.insert(calls, { method = "PATCH", endpoint = endpoint, payload = payload, opts = opts })
            return nil
        end,
        delete = function(_self, endpoint, opts)
            table.insert(calls, { method = "DELETE", endpoint = endpoint, opts = opts })
            return true
        end,
    }
end

describe("StageInstance.new", function()
    it("reads core fields from the payload", function()
        local instance = StageInstance.new(instance_payload())

        assert.equals("s1", instance.id)
        assert.equals("c1", instance.channel_id)
        assert.equals("g1", instance.guild_id)
        assert.equals("General", instance.topic)
        assert.equals(2, instance.privacy_level)
        assert.is_false(instance.discoverable_disabled)
        assert.equals("e1", instance.scheduled_event_id)
    end)

    it("falls back to guild.id when the payload has no guild_id", function()
        local data = instance_payload()
        data.guild_id = nil
        local guild = { id = "g2" }

        local instance = StageInstance.new(data, guild)
        assert.equals("g2", instance.guild_id)
    end)

    it("falls back to guild.http when no http is given directly", function()
        local guild = { id = "g2", http = {} }
        local instance = StageInstance.new(instance_payload(), guild)
        assert.equals(guild.http, instance.http)
    end)

    it("defaults discoverable_disabled to false when absent", function()
        local data = instance_payload()
        data.discoverable_disabled = nil
        local instance = StageInstance.new(data)
        assert.is_false(instance.discoverable_disabled)
    end)
end)

describe("StageInstance:edit", function()
    it("errors when no http client is attached", function()
        local instance = StageInstance.new(instance_payload())
        assert.has_error(function()
            instance:edit({ topic = "x" })
        end)
    end)

    it("PATCHes the stage-instances endpoint and updates self", function()
        local http = fake_http()
        local instance = StageInstance.new(instance_payload(), nil, http)

        instance:edit({ topic = "Renamed", privacy_level = 1, reason = "clarify" })

        assert.equals("PATCH", http.calls[1].method)
        assert.equals("/stage-instances/c1", http.calls[1].endpoint)
        assert.equals("Renamed", http.calls[1].payload.topic)
        assert.equals(1, http.calls[1].payload.privacy_level)
        assert.equals("clarify", http.calls[1].opts.reason)
        assert.equals("Renamed", instance.topic)
        assert.equals(1, instance.privacy_level)
    end)

    it("only sends fields that were set", function()
        local http = fake_http()
        local instance = StageInstance.new(instance_payload(), nil, http)

        instance:edit({ topic = "Renamed only" })

        assert.equals("Renamed only", http.calls[1].payload.topic)
        assert.is_nil(http.calls[1].payload.privacy_level)
        assert.equals(2, instance.privacy_level)
    end)
end)

describe("StageInstance:delete", function()
    it("errors when no http client is attached", function()
        local instance = StageInstance.new(instance_payload())
        assert.has_error(function()
            instance:delete()
        end)
    end)

    it("DELETEs the stage-instances endpoint", function()
        local http = fake_http()
        local instance = StageInstance.new(instance_payload(), nil, http)

        instance:delete("no longer needed")

        assert.equals("DELETE", http.calls[1].method)
        assert.equals("/stage-instances/c1", http.calls[1].endpoint)
        assert.equals("no longer needed", http.calls[1].opts.reason)
    end)
end)
