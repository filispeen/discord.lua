-- lib/cache/policy.lua
-- Cache Policy Configuration
--
-- Public Contract:
--   Policy.new(ttl_ms, max_entries) -> Policy
--     Creates a new cache policy.
--
--   Policy:get_ttl_ms() -> number
--     Gets the TTL in milliseconds.
--
--   Policy:get_max_entries() -> number
--     Gets the max entries.
--
--   Policy:should_cache() -> boolean
--     Checks if resource should be cached.
--
--   Policy:is_expired(entry) -> boolean
--     Checks if entry is expired.
--
--   Policy:create_default() -> table
--     Gets default policy for each resource type.

local class = require("core.class")

-- Default cache policies
local DEFAULT_POLICIES = {
    guild = { ttl_ms = 300000, max_entries = 1000 },       -- 5 minutes
    channel = { ttl_ms = 300000, max_entries = 1000 },     -- 5 minutes
    role = { ttl_ms = 300000, max_entries = 500 },         -- 5 minutes
    member = { ttl_ms = 0, max_entries = 10000 },          -- No TTL, large cache
    user = { ttl_ms = 3600000, max_entries = 10000 },      -- 1 hour
    message = { ttl_ms = 60000, max_entries = 50 },        -- 1 minute
    sticker = { ttl_ms = 3600000, max_entries = 100 },     -- 1 hour
    emoji = { ttl_ms = 3600000, max_entries = 100 },       -- 1 hour
    webhook = { ttl_ms = 3600000, max_entries = 100 },     -- 1 hour
    invite = { ttl_ms = 0, max_entries = 1000 },           -- No TTL, frequent updates
}

-- Policy class
local Policy = class("Policy")

-- Create a new Policy
function Policy.new(ttl_ms, max_entries)
    local self = {
        ttl_ms = ttl_ms or 0,
        max_entries = max_entries or 100,
    }
    setmetatable(self, { __index = Policy })
    return self
end

-- Get TTL in milliseconds
function Policy:get_ttl_ms()
    return self.ttl_ms
end

-- Get max entries
function Policy:get_max_entries()
    return self.max_entries
end

-- Check if resource should be cached
function Policy:should_cache()
    return self.max_entries > 0
end

-- Check if entry is expired
function Policy:is_expired(entry, now)
    if not now then
        now = os.time() * 1000
    end

    if self.ttl_ms == 0 then
        return false
    end

    local created_at = entry.created_at
    if not created_at then
        return true
    end

    return now - created_at > self.ttl_ms
end

-- Create default policy for resource type
function Policy.create_default(_self, resource_type)
    local policy = DEFAULT_POLICIES[resource_type]
    if policy then
        return Policy.new(policy.ttl_ms, policy.max_entries)
    end
    return Policy.new(3600000, 1000)  -- Default 1 hour, 1000 entries
end

-- Get all default policies
function Policy.get_all_defaults(_self)
    return DEFAULT_POLICIES
end

return Policy
