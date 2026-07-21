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
end)
