-- spec/emitter_test.lua
-- Tests for lib/core/emitter.lua

-- Setup package path to find lib modules
package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local emitter = require("core.emitter")

-- busted.describe, busted.it, busted.assert are globals when run through busted runner
describe("emitter.lua", function()
    -- Test basic emitter creation
    it("creates an emitter", function()
        local emitter_instance = emitter()
        assert.is_true(type(emitter_instance) == "table")
    end)

    -- Test :on()
    it("allows subscribing to events", function()
        local emitter_instance = emitter()
        local called = false

        emitter_instance:on("test_event", function()
            called = true
        end)

        emitter_instance:emit("test_event")
        assert.is_true(called)
    end)

    -- Test :once()
    it("calls callback once then removes it", function()
        local emitter_instance = emitter()
        local call_count = 0

        emitter_instance:once("test_event", function()
            call_count = call_count + 1
        end)

        emitter_instance:emit("test_event")
        emitter_instance:emit("test_event")

        assert.equals(1, call_count)
    end)

    -- Test :emit()
    it("emits events with arguments", function()
        local emitter_instance = emitter()
        local received_args = nil

        emitter_instance:on("test_event", function(_, a, b, c)
            received_args = {a, b, c}
        end)

        emitter_instance:emit("test_event", 1, "two", true)
        assert.is_true(received_args[1] == 1)
        assert.is_true(received_args[2] == "two")
        assert.is_true(received_args[3] == true)
    end)

    -- Test :off()
    it("allows unsubscribing from events", function()
        local emitter_instance = emitter()
        local called = false

        local handler = function()
            called = true
        end

        emitter_instance:on("test_event", handler)
        emitter_instance:off("test_event", handler)
        emitter_instance:emit("test_event")

        assert.is_false(called)
    end)

    -- Test :off() removes all handlers
    it("removes all handlers when no function specified", function()
        local emitter_instance = emitter()
        local called = false

        emitter_instance:on("test_event", function()
            called = true
        end)

        emitter_instance:off("test_event")
        emitter_instance:emit("test_event")

        assert.is_false(called)
    end)

    -- Test method chaining
    it("returns self for method chaining", function()
        local emitter_instance = emitter()
        local result = emitter_instance
            :on("test", function() end)
            :once("test", function() end)
            :emit("test")
            :off("test")

        assert.same(emitter_instance, result)
    end)
end)
