-- spec/cache/policy_spec.lua
-- Tests for cache policy

-- Setup package path to find lib modules
package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

-- Mock luv before loading gateway modules
package.loaded["luv"] = {
    timer = {
        new = function()
            return {
                start = function() end,
                stop = function() end,
            }
        end
    },
    now = function() return 0 end
}

local Policy = require("cache.policy")

describe("Cache Policy", function()
    it("creates a new policy", function()
        local policy = Policy.new(5000, 100)
        assert.equals(5000, policy:get_ttl_ms())
        assert.equals(100, policy:get_max_entries())
    end)

    it("defaults to 0 TTL and 100 entries", function()
        local policy = Policy.new()
        assert.equals(0, policy:get_ttl_ms())
        assert.equals(100, policy:get_max_entries())
    end)

    it("should_cache returns true when max_entries > 0", function()
        local policy = Policy.new(0, 100)
        assert.is_true(policy:should_cache())

        local no_cache_policy = Policy.new(0, 0)
        assert.is_false(no_cache_policy:should_cache())
    end)

    it("is_expired returns false for no TTL", function()
        local policy = Policy.new(0, 100)
        local entry = { created_at = 0 }

        -- Entry should never be expired with no TTL
        assert.is_false(policy:is_expired(entry, 1000))
    end)

    it("is_expired returns true after TTL", function()
        local policy = Policy.new(1000, 100) -- 1 second TTL
        local entry = { created_at = 500 } -- Created 500ms ago

        -- Entry should be expired (2500 - 500 = 2000 > 1000 is true)
        assert.is_true(policy:is_expired(entry, 2500))
    end)

    it("is_expired returns false before TTL", function()
        local policy = Policy.new(1000, 100) -- 1 second TTL
        local entry = { created_at = 100 } -- Created 100ms ago

        -- Entry should not be expired (500 - 100 = 400 < 1000)
        assert.is_false(policy:is_expired(entry, 500))
    end)

    it("create_default returns policy for resource type", function()
        local policy = Policy:create_default("guild")
        assert.equals(300000, policy:get_ttl_ms()) -- 5 minutes
        assert.equals(1000, policy:get_max_entries())

        local user_policy = Policy:create_default("user")
        assert.equals(3600000, user_policy:get_ttl_ms()) -- 1 hour
    end)

    it("get_all_defaults returns all default policies", function()
        local defaults = Policy:get_all_defaults()
        assert.is_table(defaults)
        assert.is_true(defaults.guild ~= nil)
        assert.is_true(defaults.channel ~= nil)
        assert.is_true(defaults.role ~= nil)
    end)
end)
