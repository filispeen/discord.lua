-- lib/http/ratelimiter.lua
-- Rate limiter for Discord API requests
--
-- Public Contract:
--   Bucket.new() -> bucket_table
--     Creates a new rate limit bucket with default Discord API limits.
--     Returns: bucket_table with rate_limit, time_remaining, reset_after fields
--
--   Bucket:consume() -> boolean
--     Attempts to consume a request from the bucket.
--     Returns: true if successful, false if rate limited
--
--   Bucket:update(headers) -> nil
--     Updates bucket state from HTTP response headers.
--     Reads X-RateLimit-Remaining, X-RateLimit-Reset-After, Retry-After
--
--   Bucket:isAvailable() -> boolean
--     Checks if a request can be made now.
--
--   Manager.new() -> manager_table
--     Creates a new rate limit manager.
--     Returns: manager_table with get_bucket, update_bucket, is_rate_limited methods
--
--   Manager:get_bucket(path) -> bucket_table
--     Gets or creates a bucket for a specific API path.
--
--   Manager:update_bucket(path, headers) -> nil
--     Updates a bucket with new rate limit headers.
--
--   Manager:is_rate_limited(path) -> boolean
--     Checks if a specific path is currently rate limited.
--
--   Manager:is_global_rate_limited() -> boolean
--     Checks if global rate limit is reached.

local M = {}

-- Default Discord API rate limit settings
M.DEFAULTS = {
    rate_limit = 1,          -- requests per second (Discord uses per-second buckets)
    time_remaining = 1,      -- seconds until next request allowed
    reset_after = 1,         -- seconds until bucket resets
}

M.Bucket = {}
M.Bucket.__index = M.Bucket

-- Create a new rate limit bucket
function M.Bucket.new()
    local self = {}
    setmetatable(self, {
        __index = M.Bucket
    })

    -- State
    self.rate_limit = M.DEFAULTS.rate_limit
    self.time_remaining = M.DEFAULTS.time_remaining
    self.reset_after = M.DEFAULTS.reset_after
    self.remaining = M.DEFAULTS.rate_limit
    self.limit = M.DEFAULTS.rate_limit

    return self
end

-- Check if a request can be made
function M.Bucket:isAvailable()
    return self.remaining > 0
end

-- Attempt to consume a request from the bucket
function M.Bucket:consume()
    if self.remaining > 0 then
        self.remaining = self.remaining - 1
        return true
    end
    return false
end

-- Update bucket state from HTTP response headers
function M.Bucket:update(headers)
    self.remaining = tonumber(headers["X-RateLimit-Remaining"] or self.remaining)
    self.limit = tonumber(headers["X-RateLimit-Limit"] or self.limit)

    -- Calculate reset time
    local reset = tonumber(headers["X-RateLimit-Reset-After"] or 0)
    if reset then
        self.reset_after = reset
    else
        -- If no reset_after header, estimate based on current remaining
        if self.remaining == 0 then
            self.reset_after = self.limit  -- worst case: wait for full bucket
        else
            self.reset_after = 1  -- minimum 1 second for Discord API
        end
    end

    -- Update time_remaining based on reset_after
    if self.remaining == 0 then
        self.time_remaining = self.reset_after
    end
end

-- Check if we're rate limited (remaining == 0 and time_remaining > 0)
function M.Bucket:isRateLimited()
    return self.remaining == 0 and self.time_remaining > 0
end

-- Get estimated seconds until rate limit resets
function M.Bucket:getRetryAfter()
    if self:isRateLimited() then
        return self.time_remaining
    end
    return 0
end

-- Rate limit manager for multiple API paths
M.Manager = {}
M.Manager.__index = M.Manager

-- Create a new rate limit manager
function M.Manager.new()
    local self = setmetatable({
        buckets = {},  -- [path] = Bucket
        global_remaining = 10,  -- Discord has a global rate limit of ~10 req/sec
        global_limit = 10,
        global_reset = 0,
    }, M.Manager)

    return self
end

-- Get or create a bucket for a specific path
function M.Manager:get_bucket(path)
    if not self.buckets[path] then
        self.buckets[path] = M.Bucket.new()
    end
    return self.buckets[path]
end

-- Update a bucket with new rate limit headers
function M.Manager:update_bucket(path, headers)
    if self.buckets[path] then
        self.buckets[path]:update(headers)
    end
end

-- Check if a path is rate limited
function M.Manager:is_rate_limited(path)
    local bucket = self:get_bucket(path)
    return bucket:isRateLimited()
end

-- Check if globally rate limited
function M.Manager:is_global_rate_limited()
    return self.global_remaining == 0 and self.global_time_remaining > 0
end

-- Get global retry after
function M.Manager:get_global_retry_after()
    if self:is_global_rate_limited() then
        return self.global_time_remaining
    end
    return 0
end

-- Consume a global request (for global rate limit)
function M.Manager:consume_global()
    if self.global_remaining > 0 then
        self.global_remaining = self.global_remaining - 1
        return true
    end
    return false
end

-- Update global rate limit from headers
function M.Manager:update_global(headers)
    self.global_remaining = tonumber(headers["X-RateLimit-Global-Remaining"] or 10)
    self.global_limit = tonumber(headers["X-RateLimit-Global-Limit"] or 10)
    self.global_time_remaining = tonumber(headers["Retry-After"] or 0)
end

-- Get all buckets
function M.Manager:get_all_buckets()
    return self.buckets
end

-- Set global rate limit state (for manual control)
function M.Manager:set_global_remaining(remaining, limit, reset)
    self.global_remaining = remaining or self.global_remaining
    self.global_limit = limit or self.global_limit
    self.global_time_remaining = reset or 0
end

return {
    Bucket = M.Bucket,
    Manager = M.Manager,
    DEFAULTS = M.DEFAULTS,
}
