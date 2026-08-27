-- spec/models/integration_spec.lua
-- Tests for Integration models

require("spec_helper")

local Integration = require("./models/integration")
local IntegrationAccount = Integration.IntegrationAccount
local IntegrationApplication = Integration.IntegrationApplication
local BaseIntegration = Integration.Integration
local StreamIntegration = Integration.StreamIntegration
local BotIntegration = Integration.BotIntegration
local from_data = Integration.from_data

local function stream_payload()
    return {
        id = "i1",
        guild_id = "g1",
        type = "twitch",
        name = "CoolStreamer",
        enabled = true,
        account = { id = "a1", name = "coolstreamer" },
        user = { id = "u1", username = "mod" },
        revoked = false,
        expire_behavior = 1,
        expire_grace_period = 7,
        synced_at = "2024-01-01T00:00:00Z",
        role_id = "r1",
        syncing = false,
        enable_emoticons = true,
        subscriber_count = 42,
    }
end

local function bot_payload()
    return {
        id = "i2",
        guild_id = "g1",
        type = "discord",
        name = "Some App",
        enabled = true,
        account = { id = "a2", name = "Some App" },
        application = {
            id = "app1",
            name = "Some App",
            icon = "hash",
            description = "desc",
            summary = "sum",
            bot = { id = "b1", username = "SomeAppBot" },
        },
    }
end

local function plain_payload()
    return {
        id = "i3",
        guild_id = "g1",
        type = "steam",
        name = "Steam",
        enabled = false,
        account = { id = "a3", name = "steam-account" },
    }
end

local function fake_http()
    local calls = {}
    return {
        calls = calls,
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

describe("IntegrationAccount", function()
    it("reads id and name", function()
        local account = IntegrationAccount.new({ id = "a1", name = "coolstreamer" })
        assert.equals("a1", account.id)
        assert.equals("coolstreamer", account.name)
    end)
end)

describe("IntegrationApplication", function()
    it("reads fields and keeps bot user raw", function()
        local app = IntegrationApplication.new(bot_payload().application)
        assert.equals("app1", app.id)
        assert.equals("Some App", app.name)
        assert.equals("hash", app.icon)
        assert.equals("desc", app.description)
        assert.equals("sum", app.summary)
        assert.equals("b1", app.user.id)
    end)
end)

describe("Integration.new", function()
    it("reads base fields from the payload", function()
        local integration = BaseIntegration.new(plain_payload())

        assert.equals("i3", integration.id)
        assert.equals("g1", integration.guild_id)
        assert.equals("steam", integration.type)
        assert.equals("Steam", integration.name)
        assert.is_false(integration.enabled)
        assert.equals("a3", integration.account.id)
    end)

    it("falls back to guild.id when the payload has no guild_id", function()
        local data = plain_payload()
        data.guild_id = nil
        local guild = { id = "g2" }

        local integration = BaseIntegration.new(data, guild)
        assert.equals("g2", integration.guild_id)
    end)

    it("errors on delete when no http client is attached", function()
        local integration = BaseIntegration.new(plain_payload())
        assert.has_error(function()
            integration:delete()
        end)
    end)

    it("deletes through the attached http client", function()
        local http = fake_http()
        local integration = BaseIntegration.new(plain_payload(), nil, http)

        integration:delete("cleanup")

        assert.equals("DELETE", http.calls[1].method)
        assert.equals("/guilds/g1/integrations/i3", http.calls[1].endpoint)
        assert.equals("cleanup", http.calls[1].opts.reason)
    end)
end)

describe("StreamIntegration.new", function()
    it("reads stream-specific fields from the payload", function()
        local integration = StreamIntegration.new(stream_payload())

        assert.equals("i1", integration.id)
        assert.is_false(integration.revoked)
        assert.equals(1, integration.expire_behaviour)
        assert.equals(7, integration.expire_grace_period)
        assert.equals("2024-01-01T00:00:00Z", integration.synced_at)
        assert.equals("r1", integration.role_id)
        assert.is_false(integration.syncing)
        assert.is_true(integration.enable_emoticons)
        assert.equals(42, integration.subscriber_count)
    end)

    it("inherits delete from Integration", function()
        local http = fake_http()
        local integration = StreamIntegration.new(stream_payload(), nil, http)

        integration:delete()

        assert.equals("DELETE", http.calls[1].method)
        assert.equals("/guilds/g1/integrations/i1", http.calls[1].endpoint)
    end)

    describe(":edit", function()
        it("errors when no http client is attached", function()
            local integration = StreamIntegration.new(stream_payload())
            assert.has_error(function()
                integration:edit({ enable_emoticons = false })
            end)
        end)

        it("PATCHes the integration endpoint and updates self", function()
            local http = fake_http()
            local integration = StreamIntegration.new(stream_payload(), nil, http)

            integration:edit({ expire_behaviour = 0, expire_grace_period = 14, enable_emoticons = false })

            assert.equals("PATCH", http.calls[1].method)
            assert.equals("/guilds/g1/integrations/i1", http.calls[1].endpoint)
            assert.equals(0, http.calls[1].payload.expire_behavior)
            assert.equals(14, http.calls[1].payload.expire_grace_period)
            assert.is_false(http.calls[1].payload.enable_emoticons)
            assert.equals(0, integration.expire_behaviour)
            assert.equals(14, integration.expire_grace_period)
            assert.is_false(integration.enable_emoticons)
        end)

        it("only sends fields that were set", function()
            local http = fake_http()
            local integration = StreamIntegration.new(stream_payload(), nil, http)

            integration:edit({ enable_emoticons = false })

            assert.is_nil(http.calls[1].payload.expire_behavior)
            assert.is_nil(http.calls[1].payload.expire_grace_period)
            assert.is_false(http.calls[1].payload.enable_emoticons)
        end)
    end)

    describe(":sync", function()
        it("errors when no http client is attached", function()
            local integration = StreamIntegration.new(stream_payload())
            assert.has_error(function()
                integration:sync()
            end)
        end)

        it("POSTs the sync endpoint and updates synced_at", function()
            local http = fake_http()
            local integration = StreamIntegration.new(stream_payload(), nil, http)
            local before = integration.synced_at

            integration:sync()

            assert.equals("POST", http.calls[1].method)
            assert.equals("/guilds/g1/integrations/i1/sync", http.calls[1].endpoint)
            assert.is_not_nil(integration.synced_at)
            assert.is_not.equals(before, integration.synced_at)
        end)
    end)
end)

describe("BotIntegration.new", function()
    it("reads the application field", function()
        local integration = BotIntegration.new(bot_payload())

        assert.equals("i2", integration.id)
        assert.equals("app1", integration.application.id)
        assert.equals("Some App", integration.application.name)
        assert.equals("b1", integration.application.user.id)
    end)

    it("inherits delete from Integration", function()
        local http = fake_http()
        local integration = BotIntegration.new(bot_payload(), nil, http)

        integration:delete()

        assert.equals("DELETE", http.calls[1].method)
        assert.equals("/guilds/g1/integrations/i2", http.calls[1].endpoint)
    end)
end)

describe("Integration.from_data", function()
    it("builds a BotIntegration for type discord", function()
        local integration = from_data(bot_payload())
        assert.is_true(getmetatable(integration).__index == BotIntegration
            or getmetatable(integration) == BotIntegration)
        assert.equals("app1", integration.application.id)
    end)

    it("builds a StreamIntegration for type twitch/youtube", function()
        local twitch = from_data(stream_payload())
        assert.equals(1, twitch.expire_behaviour)

        local yt_data = stream_payload()
        yt_data.type = "youtube"
        local youtube = from_data(yt_data)
        assert.equals(1, youtube.expire_behaviour)
    end)

    it("builds a base Integration for anything else", function()
        local integration = from_data(plain_payload())
        assert.equals("steam", integration.type)
        assert.is_nil(integration.application)
        assert.is_nil(integration.expire_behaviour)
    end)
end)
