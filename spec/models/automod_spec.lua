-- spec/models/automod_spec.lua
-- Tests for AutoMod models

require("spec_helper")

local AutoMod = require("./models/automod")
local AutoModRule = AutoMod.AutoModRule
local AutoModAction = AutoMod.AutoModAction
local AutoModActionMetadata = AutoMod.AutoModActionMetadata
local AutoModTriggerMetadata = AutoMod.AutoModTriggerMetadata

local function fake_http()
    local calls = {}
    return {
        calls = calls,
        patch = function(_self, endpoint, payload, opts)
            table.insert(calls, { method = "PATCH", endpoint = endpoint, payload = payload, opts = opts })
            return {
                id = "1",
                guild_id = "g1",
                name = payload.name or "Spam filter",
                event_type = payload.event_type or 1,
                trigger_type = 1,
                actions = payload.actions or { { type = 1, metadata = {} } },
                enabled = payload.enabled,
                exempt_roles = payload.exempt_roles or {},
                exempt_channels = payload.exempt_channels or {},
            }
        end,
        delete = function(_self, endpoint, opts)
            table.insert(calls, { method = "DELETE", endpoint = endpoint, opts = opts })
            return true
        end,
    }
end

local function rule_payload()
    return {
        id = "1",
        guild_id = "g1",
        name = "Spam filter",
        creator_id = "u1",
        event_type = 1,
        trigger_type = 1,
        trigger_metadata = { keyword_filter = { "badword" } },
        actions = {
            { type = 1, metadata = { custom_message = "blocked" } },
        },
        enabled = true,
        exempt_roles = { "r1" },
        exempt_channels = { "c1" },
    }
end

describe("AutoModActionMetadata", function()
    it("only includes fields that were set", function()
        local metadata = AutoModActionMetadata.new({ channel_id = "c1" })
        local dict = metadata:to_dict()

        assert.equals("c1", dict.channel_id)
        assert.is_nil(dict.duration_seconds)
        assert.is_nil(dict.custom_message)
    end)

    it("maps timeout_duration to duration_seconds", function()
        local metadata = AutoModActionMetadata.new({ timeout_duration = 60 })
        assert.equals(60, metadata:to_dict().duration_seconds)
    end)

    it("round trips through from_dict", function()
        local metadata = AutoModActionMetadata.from_dict({ duration_seconds = 30, custom_message = "no" })
        assert.equals(30, metadata.timeout_duration)
        assert.equals("no", metadata.custom_message)
    end)
end)

describe("AutoModAction", function()
    it("builds a dict with type and metadata", function()
        local action = AutoModAction.new(3, AutoModActionMetadata.new({ timeout_duration = 60 }))
        local dict = action:to_dict()

        assert.equals(3, dict.type)
        assert.equals(60, dict.metadata.duration_seconds)
    end)

    it("defaults metadata when none is given", function()
        local action = AutoModAction.new(1)
        assert.same({}, action:to_dict().metadata)
    end)

    it("round trips through from_dict", function()
        local action = AutoModAction.from_dict({ type = 2, metadata = { channel_id = "c1" } })
        assert.equals(2, action.type)
        assert.equals("c1", action.metadata.channel_id)
    end)
end)

describe("AutoModTriggerMetadata", function()
    it("only includes fields that were set", function()
        local metadata = AutoModTriggerMetadata.new({ keyword_filter = { "a" } })
        local dict = metadata:to_dict()

        assert.same({ "a" }, dict.keyword_filter)
        assert.is_nil(dict.presets)
        assert.is_nil(dict.mention_total_limit)
    end)

    it("round trips through from_dict", function()
        local metadata = AutoModTriggerMetadata.from_dict({ mention_total_limit = 5, presets = { 1, 2 } })
        assert.equals(5, metadata.mention_total_limit)
        assert.same({ 1, 2 }, metadata.presets)
    end)
end)

describe("AutoModRule", function()
    it("creates a new rule from API data", function()
        local rule = AutoModRule.new(rule_payload())

        assert.equals("1", rule.id)
        assert.equals("g1", rule.guild_id)
        assert.equals("Spam filter", rule.name)
        assert.equals("u1", rule.creator_id)
        assert.equals(1, rule.event_type)
        assert.equals(1, rule.trigger_type)
        assert.equals("badword", rule.trigger_metadata.keyword_filter[1])
        assert.equals(1, #rule.actions)
        assert.equals(1, rule.actions[1].type)
        assert.equals("blocked", rule.actions[1].metadata.custom_message)
        assert.is_true(rule.enabled)
        assert.same({ "r1" }, rule.exempt_role_ids)
        assert.same({ "c1" }, rule.exempt_channel_ids)
    end)

    it("falls back to guild.id when the payload has no guild_id", function()
        local data = rule_payload()
        data.guild_id = nil
        local guild = { id = "g2" }

        local rule = AutoModRule.new(data, guild)
        assert.equals("g2", rule.guild_id)
    end)

    it("edits the rule through the attached http client", function()
        local http = fake_http()
        local rule = AutoModRule.new(rule_payload(), nil, http)

        rule:edit({ name = "Renamed filter" })

        assert.equals("PATCH", http.calls[1].method)
        assert.equals("/guilds/g1/auto-moderation/rules/1", http.calls[1].endpoint)
        assert.equals("Renamed filter", http.calls[1].payload.name)
        assert.equals("Renamed filter", rule.name)
    end)

    it("serializes trigger_metadata and actions when editing", function()
        local http = fake_http()
        local rule = AutoModRule.new(rule_payload(), nil, http)

        rule:edit({
            trigger_metadata = AutoModTriggerMetadata.new({ keyword_filter = { "worse" } }),
            actions = { AutoModAction.new(3, AutoModActionMetadata.new({ timeout_duration = 60 })) },
            enabled = false,
            exempt_role_ids = { "r2" },
            exempt_channel_ids = { "c2" },
            reason = "cleanup",
        })

        local payload = http.calls[1].payload
        assert.same({ "worse" }, payload.trigger_metadata.keyword_filter)
        assert.equals(3, payload.actions[1].type)
        assert.equals(60, payload.actions[1].metadata.duration_seconds)
        assert.is_false(payload.enabled)
        assert.same({ "r2" }, payload.exempt_roles)
        assert.same({ "c2" }, payload.exempt_channels)
        assert.equals("cleanup", http.calls[1].opts.reason)
    end)

    it("deletes the rule through the attached http client", function()
        local http = fake_http()
        local rule = AutoModRule.new(rule_payload(), nil, http)

        rule:delete("no longer needed")

        assert.equals("DELETE", http.calls[1].method)
        assert.equals("/guilds/g1/auto-moderation/rules/1", http.calls[1].endpoint)
        assert.equals("no longer needed", http.calls[1].opts.reason)
    end)

    it("errors on edit when no http client is attached", function()
        local rule = AutoModRule.new(rule_payload())

        assert.has_error(function()
            rule:edit({ name = "x" })
        end)
    end)

    it("errors on delete when no http client is attached", function()
        local rule = AutoModRule.new(rule_payload())

        assert.has_error(function()
            rule:delete()
        end)
    end)
end)
