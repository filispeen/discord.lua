require("spec_helper")

local AppInfo = require("./models/application").AppInfo
local Metadata = require("./models/application_role_connection")
local Onboarding = require("./models/onboarding")
local Monetization = require("./models/monetization")
local Guild = require("./models/guild")
local User = require("./models/user")

describe("application metadata models", function()
    it("builds application info with owner, team and install params", function()
        local info = AppInfo.new({
            id = "app",
            name = "Test app",
            owner = { id = "owner", username = "owner", discriminator = "0" },
            team = {
                id = "team",
                name = "Team",
                owner_user_id = "owner",
                members = { { membership_state = 2, role = "admin", user = { id = "owner", username = "owner", discriminator = "0" } } },
            },
            install_params = { scopes = { "bot" }, permissions = "8" },
            integration_types_config = { ["0"] = { oauth2_install_params = { scopes = { "applications.commands" } } } },
        })

        assert.equals("app", info.id)
        assert.equals("owner", info.owner.id)
        assert.equals("owner", info.team:get_owner().id)
        assert.equals("bot", info.install_params.scopes[1])
        assert.equals("applications.commands", info.integration_types_config["0"].oauth2_install_params.scopes[1])
    end)

    it("serializes role connection metadata", function()
        local metadata = Metadata.new({ type = 2, key = "level", name = "Level", description = "Current level" })
        local data = metadata:to_dict()

        assert.equals(2, data.type)
        assert.equals("level", data.key)
    end)

    it("models user primary guild and collectibles", function()
        local user = User.new({
            id = "u1",
            username = "name",
            discriminator = "0",
            primary_guild = { identity_guild_id = "g1", identity_enabled = true, tag = "tag" },
            collectibles = { nameplate = { sku_id = "sku", palette = "red", label = "Label", asset = "asset" } },
        })

        assert.equals("g1", user.primary_guild.identity_guild_id)
        assert.equals("sku", user.collectibles.nameplate.sku_id)
    end)
end)

describe("onboarding and monetization models", function()
    it("serializes onboarding prompts and edits through its guild", function()
        local calls = {}
        local http = {
            put = function(_, endpoint, payload)
                calls[#calls + 1] = { endpoint = endpoint, payload = payload }
                return { guild_id = "g1", enabled = true, prompts = payload.prompts, default_channel_ids = payload.default_channel_ids }
            end,
        }
        local guild = Guild.new({ id = "g1", name = "Guild" }, http)
        local flow = Onboarding.Onboarding.new({
            guild_id = "g1",
            prompts = {
                { id = "p1", type = 0, title = "Pick", single_select = true, required = true, in_onboarding = true, options = {
                    { id = "o1", title = "Lua", channel_ids = { "c1" }, role_ids = { "r1" } },
                } },
            },
        }, guild)

        local updated = flow:edit({ prompts = flow.prompts, default_channel_ids = { "c1" }, enabled = true })

        assert.equals("/guilds/g1/onboarding", calls[1].endpoint)
        assert.equals("Lua", calls[1].payload.prompts[1].options[1].title)
        assert.is_true(updated.enabled)
    end)

    it("consumes an entitlement and lists SKU subscriptions", function()
        local calls = {}
        local http = {
            post = function(_, endpoint)
                calls[#calls + 1] = endpoint
            end,
            get = function(_, endpoint)
                calls[#calls + 1] = endpoint
                return { { id = "s1", user_id = "u1", sku_ids = { "sku" }, entitlement_ids = {} } }
            end,
        }
        local entitlement = Monetization.Entitlement.new({ id = "e1", application_id = "app", sku_id = "sku" }, http)
        entitlement:consume()
        local subscriptions = Monetization.SKU.new({ id = "sku", application_id = "app" }, http):fetch_subscriptions({ user_id = "u1" })

        assert.equals("/applications/app/entitlements/e1/consume", calls[1])
        assert.is_true(entitlement.consumed)
        assert.equals("/skus/sku/subscriptions?user_id=u1", calls[2])
        assert.equals("s1", subscriptions[1].id)
    end)

    it("exposes application and commerce client APIs", function()
        local calls = {}
        local http = {
            get = function(_, endpoint)
                calls[#calls + 1] = endpoint
                if endpoint == "/oauth2/applications/@me" then return { id = "app", name = "App" } end
                if endpoint == "/applications/app/skus" then return { { id = "sku", application_id = "app", name = "Premium" } } end
                return { { id = "e1", application_id = "app", sku_id = "sku" } }
            end,
        }
        local Client = require("./models/client")
        local client = Client.new("token")
        client.http = http

        local app = client:application_info()
        local skus = client:fetch_skus()
        local entitlements = client:fetch_entitlements({ limit = 1 })

        assert.equals("app", app.id)
        assert.equals("Premium", skus[1].name)
        assert.equals("e1", entitlements[1].id)
        assert.equals("/applications/app/entitlements?limit=1", calls[3])
    end)

    it("emits typed and cached entitlement and subscription gateway events", function()
        local Client = require("./models/client")
        local client = Client.new("token")
        local handlers = {}
        client.gateway = {
            on_shard_ready = function() end,
            on_shard_error = function() end,
            on_shard_disconnect = function() end,
            on_ready = function() end,
            on_dispatch = function(_, name, callback) handlers[name] = callback end,
            start = function() end,
        }
        package.loaded["../gateway/manager"] = { new = function() return client.gateway end }
        client:start_gateway()
        package.loaded["../gateway/manager"] = nil

        local entitlement_event
        local subscription_event
        client:on("entitlement_create", function(value) entitlement_event = value end)
        client:on("subscription_create", function(value) subscription_event = value end)
        handlers["ENTITLEMENT_CREATE"]({ id = "e1", application_id = "app", sku_id = "sku" })
        handlers["SUBSCRIPTION_CREATE"]({ id = "s1", user_id = "u1", sku_ids = { "sku" }, entitlement_ids = {} })

        assert.equals("e1", entitlement_event.id)
        assert.equals(entitlement_event, client.entitlements["e1"])
        assert.equals("s1", subscription_event.id)
        assert.equals(subscription_event, client.subscriptions["s1"])
    end)
end)
