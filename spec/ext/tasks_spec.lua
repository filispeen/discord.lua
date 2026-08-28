require("spec_helper")

local created

local mock_luv = {
    now = function()
        return 100
    end,
    new_timer = function()
        local timer = {
            stopped = false,
            closed = false,
        }
        function timer:start(delay, repeat_delay, callback)
            self.delay = delay
            self.repeat_delay = repeat_delay
            self.callback = callback
        end
        function timer:stop()
            self.stopped = true
        end
        function timer:close()
            self.closed = true
        end
        table.insert(created, timer)
        return timer
    end,
}

local function load_tasks()
    created = {}
    package.loaded["mock_luv"] = mock_luv
    package.loaded["./core/luv_compat"] = nil
    package.loaded["./ext/tasks"] = nil
    return require("./ext/tasks")
end

local function latest_timer()
    return created[#created]
end

describe("ext.tasks", function()
    after_each(function()
        package.loaded["mock_luv"] = nil
        package.loaded["./core/luv_compat"] = nil
        package.loaded["./ext/tasks"] = nil
    end)

    it("runs a callback immediately and then at its configured interval", function()
        local tasks = load_tasks()
        local calls = {}
        local loop = tasks.loop(function(value)
            table.insert(calls, value)
        end, { seconds = 2, count = 2 })

        loop:start("tick")
        assert.equals(0, latest_timer().delay)

        latest_timer().callback()
        assert.same({ "tick" }, calls)
        assert.equals(2000, latest_timer().delay)

        latest_timer().callback()
        assert.same({ "tick", "tick" }, calls)
        assert.is_false(loop:is_running())
        assert.equals(2, loop:current_loop())
    end)

    it("supports decorator-style construction", function()
        local tasks = load_tasks()
        local calls = 0
        local loop = tasks.loop({ minutes = 1, count = 1 })(function()
            calls = calls + 1
        end)

        loop:start()
        latest_timer().callback()

        assert.equals(1, calls)
        assert.is_false(loop:is_running())
    end)

    it("runs lifecycle hooks and stops before a waiting iteration", function()
        local tasks = load_tasks()
        local events = {}
        local loop = tasks.loop(function()
            table.insert(events, "callback")
        end, { seconds = 1 })

        loop:before_loop(function()
            table.insert(events, "before")
        end)
        loop:after_loop(function(cancelled)
            table.insert(events, cancelled and "cancelled" or "after")
        end)

        loop:start()
        loop:stop()

        assert.same({ "before", "after" }, events)
        assert.is_false(loop:is_running())
        assert.is_true(latest_timer().stopped)
    end)

    it("finishes after stop requested by its callback", function()
        local tasks = load_tasks()
        local loop
        local calls = 0
        loop = tasks.loop(function()
            calls = calls + 1
            loop:stop()
        end, { seconds = 1 })

        loop:start()
        latest_timer().callback()

        assert.equals(1, calls)
        assert.is_false(loop:is_running())
    end)

    it("reports errors and retries with exponential backoff when reconnect is enabled", function()
        local tasks = load_tasks()
        local attempts = 0
        local errors = {}
        local loop = tasks.loop(function()
            attempts = attempts + 1
            if attempts == 1 then
                error("temporary")
            end
        end, { seconds = 5, reconnect = true, backoff = 2, max_backoff = 8, count = 1 })

        loop:error(function(err)
            table.insert(errors, err)
        end)
        loop:start()
        latest_timer().callback()

        assert.equals(1, #errors)
        assert.is_true(errors[1]:find("temporary", 1, true) ~= nil)
        assert.equals(2000, latest_timer().delay)

        latest_timer().callback()
        assert.equals(2, attempts)
        assert.is_false(loop:is_running())
    end)

    it("stops after an error when reconnect is disabled", function()
        local tasks = load_tasks()
        local loop = tasks.loop(function()
            error("fatal")
        end, { seconds = 1 })

        loop:start()
        latest_timer().callback()

        assert.is_true(loop:failed())
        assert.is_false(loop:is_running())
    end)

    it("validates construction input", function()
        local tasks = load_tasks()

        assert.has_error(function()
            tasks.loop({}, {})
        end)
        assert.has_error(function()
            tasks.loop(function() end, { seconds = 0 })
        end)
        assert.has_error(function()
            tasks.loop(function() end, { seconds = 1, count = 0 })
        end)
    end)
end)
