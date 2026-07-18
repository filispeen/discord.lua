-- spec/http/ratelimiter_spec.lua
-- Tests for the HTTP rate limiter. Also guards against the module failing
-- to load at all: M.Bucket and M.Manager used to be referenced without
-- ever being initialized as tables, which crashed require() unconditionally.

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local ratelimiter = require("http.ratelimiter")

describe("ratelimiter", function()
    it("loads without error and exports Bucket, Manager, DEFAULTS", function()
        assert.is_not_nil(ratelimiter.Bucket)
        assert.is_not_nil(ratelimiter.Manager)
        assert.is_not_nil(ratelimiter.DEFAULTS)
    end)

    describe("Bucket", function()
        it("creates a bucket with default limits", function()
            local bucket = ratelimiter.Bucket.new()
            assert.equals(ratelimiter.DEFAULTS.rate_limit, bucket.remaining)
        end)

        it("is available when remaining is above zero", function()
            local bucket = ratelimiter.Bucket.new()
            assert.is_true(bucket:isAvailable())
        end)

        it("consume decrements remaining and returns true", function()
            local bucket = ratelimiter.Bucket.new()
            local ok = bucket:consume()
            assert.is_true(ok)
            assert.equals(0, bucket.remaining)
        end)

        it("consume returns false once remaining is exhausted", function()
            local bucket = ratelimiter.Bucket.new()
            bucket:consume()
            local ok = bucket:consume()
            assert.is_false(ok)
        end)

        it("isRateLimited is true once remaining hits zero", function()
            local bucket = ratelimiter.Bucket.new()
            bucket:consume()
            assert.is_true(bucket:isRateLimited())
        end)

        it("updates remaining and limit from response headers", function()
            local bucket = ratelimiter.Bucket.new()
            bucket:update({
                ["X-RateLimit-Remaining"] = "5",
                ["X-RateLimit-Limit"] = "10",
                ["X-RateLimit-Reset-After"] = "2.5",
            })

            assert.equals(5, bucket.remaining)
            assert.equals(10, bucket.limit)
            assert.equals(2.5, bucket.reset_after)
        end)

        it("getRetryAfter returns 0 when not rate limited", function()
            local bucket = ratelimiter.Bucket.new()
            assert.equals(0, bucket:getRetryAfter())
        end)
    end)

    describe("Manager", function()
        it("creates buckets on demand per path", function()
            local manager = ratelimiter.Manager.new()
            local bucket = manager:get_bucket("/channels/1/messages")

            assert.is_not_nil(bucket)
            assert.equals(bucket, manager:get_bucket("/channels/1/messages"))
        end)

        it("is_rate_limited reflects the underlying bucket state", function()
            local manager = ratelimiter.Manager.new()
            local bucket = manager:get_bucket("/channels/1/messages")
            bucket:consume()

            assert.is_true(manager:is_rate_limited("/channels/1/messages"))
        end)

        it("consume_global decrements the global remaining count", function()
            local manager = ratelimiter.Manager.new()
            local ok = manager:consume_global()

            assert.is_true(ok)
            assert.equals(9, manager.global_remaining)
        end)

        it("update_global sets remaining, limit, and retry-after", function()
            local manager = ratelimiter.Manager.new()
            manager:update_global({
                ["X-RateLimit-Global-Remaining"] = "3",
                ["X-RateLimit-Global-Limit"] = "10",
                ["Retry-After"] = "1.2",
            })

            assert.equals(3, manager.global_remaining)
            assert.equals(10, manager.global_limit)
            assert.equals(1.2, manager.global_time_remaining)
        end)
    end)
end)
