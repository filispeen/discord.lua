-- spec/core/errors_spec.lua
-- Tests for core error classes

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local errors = require("core.errors")

describe("errors", function()
    describe("TimeoutError", function()
        it("defaults to a generic message", function()
            local err = errors.TimeoutError.new()
            assert.equals("Timed out waiting for event", err.message)
        end)

        it("accepts a custom message", function()
            local err = errors.TimeoutError.new("Timed out waiting for message")
            assert.equals("Timed out waiting for message", err.message)
        end)

        it("is a DiscordException", function()
            local class = require("core.class")
            local err = errors.TimeoutError.new("boom")
            assert.is_true(class.isInstanceOf(err, errors.DiscordException))
        end)
    end)

    describe("DiscordException", function()
        it("stores message correctly (not shifted into self)", function()
            local err = errors.DiscordException.new("something broke")
            assert.equals("something broke", err.message)
        end)

        it("__tostring returns the message", function()
            local err = errors.DiscordException.new("something broke")
            assert.equals("something broke", tostring(err))
        end)

        it("create() builds the same shape as new()", function()
            local err = errors.DiscordException.create("via create")
            assert.equals("via create", err.message)
        end)
    end)

    describe("HTTPException", function()
        it("stores message, status_code, and data in the right fields", function()
            local err = errors.HTTPException.new("bad request", 400, { code = 50001 })
            assert.equals("bad request", err.message)
            assert.equals(400, err.status_code)
            assert.equals(50001, err.data.code)
        end)

        it("defaults data to nil when not given", function()
            local err = errors.HTTPException.new("server error", 500)
            assert.is_nil(err.data)
        end)

        it("__tostring includes the status code", function()
            local err = errors.HTTPException.new("bad request", 400)
            assert.is_not_nil(tostring(err):find("400"))
        end)

        it("is a DiscordException", function()
            local class = require("core.class")
            local err = errors.HTTPException.new("bad request", 400)
            assert.is_true(class.isInstanceOf(err, errors.DiscordException))
        end)
    end)

    describe("RateLimited", function()
        it("stores message and retry_after in the right fields", function()
            local err = errors.RateLimited.new("slow down", 5)
            assert.equals("slow down", err.message)
            assert.equals(5, err.retry_after)
        end)

        it("defaults retry_after to 0 when not given", function()
            local err = errors.RateLimited.new("slow down")
            assert.equals(0, err.retry_after)
        end)
    end)

    describe("GatewayError", function()
        it("stores message and code in the right fields", function()
            local err = errors.GatewayError.new("connection closed", 4004)
            assert.equals("connection closed", err.message)
            assert.equals(4004, err.code)
        end)
    end)

    describe("NotFound", function()
        it("stores message and id in the right fields", function()
            local err = errors.NotFound.new("channel not found", "123")
            assert.equals("channel not found", err.message)
            assert.equals("123", err.id)
        end)
    end)

    describe("Forbidden", function()
        it("stores message correctly", function()
            local err = errors.Forbidden.new("missing permissions")
            assert.equals("missing permissions", err.message)
        end)
    end)
end)
