require("spec_helper")

local Route = require("./http/route")

describe("Route parity endpoints", function()
    local function fake_http()
        local calls = {}
        local http = {}
        for _, method in ipairs({ "get", "post", "put", "patch", "delete" }) do
            http[method] = function(_self, endpoint, payload)
                calls[#calls + 1] = { method = method, endpoint = endpoint, payload = payload }
                return { threads = {}, id = "result" }
            end
        end
        return http, calls
    end

    it("builds message, thread and webhook parity endpoints", function()
        local http, calls = fake_http()
        local route = Route.new(http)
        route:pin_message("c1", "m1")
        route:get_reaction_users("c1", "m1", "fire", { limit = 10, after = "u1" })
        route:get_active_threads("g1")
        route:get_archived_threads("c1", "private", { limit = 20 })
        route:create_webhook("c1", { name = "hook" })
        route:follow_channel("c1", "c2")

        assert.equals("/channels/c1/pins/m1", calls[1].endpoint)
        assert.is_truthy(calls[2].endpoint:find("/channels/c1/messages/m1/reactions/fire?", 1, true))
        assert.is_truthy(calls[2].endpoint:find("limit=10", 1, true))
        assert.is_truthy(calls[2].endpoint:find("after=u1", 1, true))
        assert.equals("/guilds/g1/threads/active", calls[3].endpoint)
        assert.equals("/channels/c1/threads/archived/private?limit=20", calls[4].endpoint)
        assert.equals("/channels/c1/webhooks", calls[5].endpoint)
        assert.equals("/channels/c1/followers", calls[6].endpoint)
    end)

    it("builds original response and followup endpoints", function()
        local http, calls = fake_http()
        local route = Route.new(http)
        route:get_original_interaction_response("app", "token")
        route:create_followup_message("app", "token", { content = "hi" })
        route:edit_followup_message("app", "token", "m1", { content = "edit" })
        route:delete_followup_message("app", "token", "m1")

        assert.equals("/webhooks/app/token/messages/@original", calls[1].endpoint)
        assert.equals("/webhooks/app/token", calls[2].endpoint)
        assert.equals("/webhooks/app/token/messages/m1", calls[3].endpoint)
        assert.equals("/webhooks/app/token/messages/m1", calls[4].endpoint)
    end)

    it("builds application, commerce, onboarding and incident endpoints", function()
        local http, calls = fake_http()
        local route = Route.new(http)
        route:get_application_role_connection_metadata("app")
        route:update_application_role_connection_metadata("app", { { key = "level" } })
        route:get_entitlements("app", { sku_ids = { "s1", "s2" }, limit = 10 })
        route:consume_entitlement("app", "e1")
        route:get_sku_subscriptions("s1", { user_id = "u1" })
        route:edit_onboarding("g1", { enabled = true })
        route:modify_guild_incident_actions("g1", { dms_disabled_until = nil })

        assert.equals("/applications/app/role-connections/metadata", calls[1].endpoint)
        assert.equals("/applications/app/role-connections/metadata", calls[2].endpoint)
        assert.is_truthy(calls[3].endpoint:find("/applications/app/entitlements?", 1, true))
        assert.is_truthy(calls[3].endpoint:find("sku_ids=s1,s2", 1, true))
        assert.equals("/applications/app/entitlements/e1/consume", calls[4].endpoint)
        assert.equals("/skus/s1/subscriptions?user_id=u1", calls[5].endpoint)
        assert.equals("/guilds/g1/onboarding", calls[6].endpoint)
        assert.equals("/guilds/g1/incident-actions", calls[7].endpoint)
    end)
end)
