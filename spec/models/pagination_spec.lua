require("spec_helper")

local Client = require("./models/client")
local SKU = require("./models/monetization").SKU
local Channel = require("./models/channel")

describe("model paginators", function()
    it("iterates application entitlements by cursor", function()
        local client = Client.new("token")
        client.application_id = "app"
        local calls = 0
        client.http = {
            get = function(_, endpoint)
                calls = calls + 1
                if endpoint:find("after=e2", 1, true) then
                    return { { id = "e1" } }
                end
                return { { id = "e3" }, { id = "e2" } }
            end,
        }

        local ids = {}
        for entitlement in client:iter_entitlements({ page_size = 2, limit = 3, after = "seed" }) do
            ids[#ids + 1] = entitlement.id
        end

        assert.same({ "e3", "e2", "e1" }, ids)
        assert.equals(2, calls)
    end)

    it("honours an archived-thread response with has_more false", function()
        local channel = Channel.new({ id = "c1" }, { id = "g1" }, {
            get = function()
                return {
                    has_more = false,
                    threads = { { id = "t2" }, { id = "t1" } },
                }
            end,
        })
        local ids = {}
        for thread in channel:iter_archived_threads({ page_size = 2 }) do
            ids[#ids + 1] = thread.id
        end

        assert.same({ "t2", "t1" }, ids)
    end)

    it("iterates SKU subscriptions", function()
        local sku = SKU.new({ id = "s1" }, {
            get = function(_, endpoint)
                if endpoint:find("after=sub2", 1, true) then
                    return { { id = "sub1" } }
                end
                return { { id = "sub3" }, { id = "sub2" } }
            end,
        })
        local ids = {}
        for subscription in sku:iter_subscriptions({ page_size = 2, limit = 3, after = "seed" }) do
            ids[#ids + 1] = subscription.id
        end

        assert.same({ "sub3", "sub2", "sub1" }, ids)
    end)
end)
