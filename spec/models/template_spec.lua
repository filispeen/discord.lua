-- spec/models/template_spec.lua
-- Tests for the Template model

require("spec_helper")

local Template = require("./models/template")

local function template_payload()
    return {
        code = "abc123",
        usage_count = 5,
        name = "My Template",
        description = "A cool server",
        creator = { id = "u1", username = "creator" },
        created_at = "2024-01-01T00:00:00Z",
        updated_at = "2024-01-02T00:00:00Z",
        source_guild_id = "g1",
        serialized_source_guild = {
            name = "Source Guild",
            icon_hash = nil,
            region = "us-east",
        },
        is_dirty = false,
    }
end

local function fake_http()
    local calls = {}
    return {
        calls = calls,
        get = function(_self, endpoint)
            table.insert(calls, { method = "GET", endpoint = endpoint })
            return nil
        end,
        put = function(_self, endpoint, payload)
            table.insert(calls, { method = "PUT", endpoint = endpoint, payload = payload })
            return nil
        end,
        patch = function(_self, endpoint, payload)
            table.insert(calls, { method = "PATCH", endpoint = endpoint, payload = payload })
            return nil
        end,
        post = function(_self, endpoint, payload)
            table.insert(calls, { method = "POST", endpoint = endpoint, payload = payload })
            return nil
        end,
        delete = function(_self, endpoint, opts)
            table.insert(calls, { method = "DELETE", endpoint = endpoint, opts = opts })
            return true
        end,
    }
end

describe("Template.new", function()
    it("reads base fields from the payload", function()
        local template = Template.new(template_payload())

        assert.equals("abc123", template.code)
        assert.equals(5, template.uses)
        assert.equals("My Template", template.name)
        assert.equals("A cool server", template.description)
        assert.equals("u1", template.creator.id)
        assert.equals("2024-01-01T00:00:00Z", template.created_at)
        assert.equals("2024-01-02T00:00:00Z", template.updated_at)
        assert.is_false(template.is_dirty)
    end)

    it("builds source_guild from the serialized payload", function()
        local template = Template.new(template_payload())

        assert.is_not_nil(template.source_guild)
        assert.equals("g1", template.source_guild.id)
        assert.equals("Source Guild", template.source_guild.name)
    end)

    it("falls back to a minimal source_guild when no serialized payload is present", function()
        local data = template_payload()
        data.serialized_source_guild = nil

        local template = Template.new(data)

        assert.is_not_nil(template.source_guild)
        assert.equals("g1", template.source_guild.id)
    end)

    it("computes the discord.new url from the code", function()
        local template = Template.new(template_payload())
        assert.equals("https://discord.new/abc123", template:url())
    end)
end)

describe("Template:sync", function()
    it("errors when no http client is attached", function()
        local template = Template.new(template_payload())
        assert.has_error(function()
            template:sync()
        end)
    end)

    it("PUTs the sync endpoint and re-applies the response", function()
        local http = fake_http()
        http.put = function(_self, endpoint, payload)
            table.insert(http.calls, { method = "PUT", endpoint = endpoint, payload = payload })
            local data = template_payload()
            data.usage_count = 6
            data.is_dirty = false
            return data
        end

        local template = Template.new(template_payload(), http)
        template:sync()

        assert.equals("PUT", http.calls[#http.calls].method)
        assert.equals("/guilds/g1/templates/abc123", http.calls[#http.calls].endpoint)
        assert.equals(6, template.uses)
    end)
end)

describe("Template:edit", function()
    it("errors when no http client is attached", function()
        local template = Template.new(template_payload())
        assert.has_error(function()
            template:edit({ name = "New Name" })
        end)
    end)

    it("PATCHes the template endpoint and re-applies the response", function()
        local http = fake_http()
        http.patch = function(_self, endpoint, payload)
            table.insert(http.calls, { method = "PATCH", endpoint = endpoint, payload = payload })
            local data = template_payload()
            data.name = payload.name
            return data
        end

        local template = Template.new(template_payload(), http)
        template:edit({ name = "New Name" })

        assert.equals("PATCH", http.calls[#http.calls].method)
        assert.equals("/guilds/g1/templates/abc123", http.calls[#http.calls].endpoint)
        assert.equals("New Name", http.calls[#http.calls].payload.name)
        assert.equals("New Name", template.name)
    end)

    it("only sends fields that were set", function()
        local http = fake_http()
        local captured
        http.patch = function(_self, endpoint, payload)
            captured = payload
            return template_payload()
        end

        local template = Template.new(template_payload(), http)
        template:edit({ description = "Updated" })

        assert.is_nil(captured.name)
        assert.equals("Updated", captured.description)
    end)
end)

describe("Template:delete", function()
    it("errors when no http client is attached", function()
        local template = Template.new(template_payload())
        assert.has_error(function()
            template:delete()
        end)
    end)

    it("DELETEs the template endpoint", function()
        local http = fake_http()
        local template = Template.new(template_payload(), http)

        template:delete()

        assert.equals("DELETE", http.calls[1].method)
        assert.equals("/guilds/g1/templates/abc123", http.calls[1].endpoint)
    end)
end)
