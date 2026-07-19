-- spec/commands/cooldown_spec.lua
-- Tests for cooldown

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local M = require("commands.cooldown")

describe("Cooldown", function()
    describe("Cooldown class", function()
        it("allows calls under the rate limit", function()
            local cd = M.Cooldown.new(2, 5)
            assert.are.equal(0, cd:update(100))
            assert.are.equal(0, cd:update(101))
        end)

        it("blocks calls over the rate limit within the window", function()
            local cd = M.Cooldown.new(1, 5)
            assert.are.equal(0, cd:update(100))
            local retry_after = cd:update(102)
            assert.is_true(retry_after > 0)
            assert.are.equal(3, retry_after)
        end)

        it("allows calls again after the window expires", function()
            local cd = M.Cooldown.new(1, 5)
            assert.are.equal(0, cd:update(100))
            assert.are.equal(0, cd:update(106))
        end)

        it("reset clears history", function()
            local cd = M.Cooldown.new(1, 5)
            cd:update(100)
            cd:reset()
            assert.are.equal(0, cd:update(101))
        end)

        it("copy returns a fresh cooldown with same rate/per", function()
            local cd = M.Cooldown.new(3, 10)
            cd:update(100)
            local copy = cd:copy()
            assert.are.equal(3, copy.rate)
            assert.are.equal(10, copy.per)
            assert.are.equal(0, #copy._calls)
        end)
    end)

    describe("BucketType", function()
        it("user buckets by author id", function()
            local ctx = { author = { id = "123" } }
            assert.are.equal("user:123", M.BucketType.user(ctx))
        end)

        it("guild buckets by guild id", function()
            local ctx = { guild = { id = "111" } }
            assert.are.equal("guild:111", M.BucketType.guild(ctx))
        end)

        it("channel buckets by channel id", function()
            local ctx = { channel = { id = "222" } }
            assert.are.equal("channel:222", M.BucketType.channel(ctx))
        end)

        it("member buckets by guild and author id", function()
            local ctx = { guild = { id = "111" }, author = { id = "123" } }
            assert.are.equal("member:111:123", M.BucketType.member(ctx))
        end)

        it("default collapses to a single bucket", function()
            local ctx = { author = { id = "123" } }
            assert.are.equal("default", M.BucketType.default(ctx))
        end)
    end)

    describe("M.cooldown", function()
        it("allows the first call within rate", function()
            local check = M.cooldown(1, 5, M.BucketType.user)
            local ctx = { author = { id = "1" } }
            assert.is_true(check.func(ctx))
        end)

        it("raises CommandOnCooldown when exceeding rate for the same bucket key", function()
            local check = M.cooldown(1, 5, M.BucketType.user)
            local ctx = { author = { id = "1" } }
            check.func(ctx)

            local ok, err = pcall(function()
                check.func(ctx)
            end)
            assert.is_false(ok)
            assert.is_true(err ~= nil)
            assert.are.equal("CommandOnCooldown", err._name)
        end)

        it("tracks separate buckets independently", function()
            local check = M.cooldown(1, 5, M.BucketType.user)
            local ctx1 = { author = { id = "1" } }
            local ctx2 = { author = { id = "2" } }
            assert.is_true(check.func(ctx1))
            assert.is_true(check.func(ctx2))
        end)
    end)

    describe("M.dynamic_cooldown", function()
        it("bypasses the cooldown when callback returns nil", function()
            local check = M.dynamic_cooldown(function(_ctx)
                return nil
            end, M.BucketType.user)
            local ctx = { author = { id = "1" } }
            assert.is_true(check.func(ctx))
            assert.is_true(check.func(ctx))
        end)

        it("enforces the cooldown template returned by callback", function()
            local check = M.dynamic_cooldown(function(_ctx)
                return M.Cooldown.new(1, 5)
            end, M.BucketType.user)
            local ctx = { author = { id = "1" } }
            assert.is_true(check.func(ctx))

            local ok = pcall(function()
                check.func(ctx)
            end)
            assert.is_false(ok)
        end)
    end)

    describe("CommandOnCooldown", function()
        it("carries retry_after", function()
            local err = M.CommandOnCooldown.new(3.5)
            assert.are.equal(3.5, err.retry_after)
        end)
    end)
end)
