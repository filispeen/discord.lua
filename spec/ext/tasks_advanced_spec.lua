require("spec_helper")

local created = {}
local mock_luv = {
    now = function() return 100 end,
    new_timer = function()
        local timer = {}
        function timer:start(delay, repeat_delay, callback)
            self.delay, self.repeat_delay, self.callback = delay, repeat_delay, callback
        end
        function timer:stop() end
        function timer:close() end
        created[#created + 1] = timer
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

describe("ext.tasks advanced semantics", function()
    after_each(function()
        package.loaded["mock_luv"] = nil
        package.loaded["./core/luv_compat"] = nil
        package.loaded["./ext/tasks"] = nil
    end)

    it("accepts one or more absolute UTC-local wall-clock times", function()
        local tasks = load_tasks()
        local loop = tasks.loop(function() end, { time = { "08:30", "17:45:10" } })

        assert.same({ 30600, 63910 }, loop._times)
        assert.is_true(loop:_absolute_delay() > 0)
    end)

    it("retries only matching errors when matchers are configured", function()
        local tasks = load_tasks()
        local calls = 0
        local loop = tasks.loop(function()
            calls = calls + 1
            if calls == 1 then
                error({ kind = "temporary" })
            end
        end, {
            seconds = 1,
            count = 1,
            reconnect = true,
            retry_exceptions = {
                function(err) return type(err) == "table" and err.kind == "temporary" end,
            },
        })

        loop:start()
        created[#created].callback()
        assert.equals(1000, created[#created].delay)
        created[#created].callback()

        assert.equals(2, calls)
        assert.is_false(loop:is_running())
    end)

    it("stops on an unmatched reconnect error", function()
        local tasks = load_tasks()
        local loop = tasks.loop(function()
            error("fatal")
        end, {
            seconds = 1,
            reconnect = true,
            retry_exceptions = { "temporary" },
        })

        loop:start()
        created[#created].callback()

        assert.is_false(loop:is_running())
        assert.is_true(loop:failed())
    end)
end)
