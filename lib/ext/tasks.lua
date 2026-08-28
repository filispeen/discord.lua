local luv = require("../core/luv_compat")

local unpack = table.unpack or unpack

local Loop = {}
Loop.__index = Loop

local function interval_ms(opts)
    local seconds = opts.seconds or 0
    local minutes = opts.minutes or 0
    local hours = opts.hours or 0
    local total = seconds + minutes * 60 + hours * 3600
    if type(total) ~= "number" or total <= 0 then
        error("tasks.loop requires a positive interval", 0)
    end
    return total * 1000
end

function Loop.new(callback, opts)
    if type(callback) ~= "function" then
        error("tasks.loop requires a callback function", 0)
    end

    opts = opts or {}
    if opts.count ~= nil and (type(opts.count) ~= "number" or opts.count <= 0 or opts.count % 1 ~= 0) then
        error("tasks.loop count must be a positive integer or nil", 0)
    end

    local self = setmetatable({}, Loop)
    self.callback = callback
    self.count = opts.count
    self.reconnect = opts.reconnect == true
    self._interval = interval_ms(opts)
    self._backoff = tonumber(opts.backoff) or 1
    self._max_backoff = tonumber(opts.max_backoff) or 300
    self._current_loop = 0
    self._running = false
    self._cancelled = false
    self._stop_requested = false
    self._failed = false
    self._in_callback = false
    self._timer = nil
    self._args = nil
    self._before = nil
    self._after = nil
    self._error = nil
    return self
end

function Loop:change_interval(opts)
    opts = opts or {}
    self._interval = interval_ms(opts)
    return self
end

function Loop:before_loop(callback)
    if type(callback) ~= "function" then
        error("before_loop callback must be a function", 0)
    end
    self._before = callback
    return callback
end

function Loop:after_loop(callback)
    if type(callback) ~= "function" then
        error("after_loop callback must be a function", 0)
    end
    self._after = callback
    return callback
end

function Loop:error(callback)
    if type(callback) ~= "function" then
        error("error callback must be a function", 0)
    end
    self._error = callback
    return callback
end

function Loop:is_running()
    return self._running
end

function Loop:failed()
    return self._failed
end

function Loop:current_loop()
    return self._current_loop
end

function Loop:next_iteration()
    return self._next_iteration
end

function Loop:_close_timer()
    if self._timer then
        self._timer:stop()
        if self._timer.close then
            self._timer:close()
        end
        self._timer = nil
    end
end

function Loop:_finish()
    self:_close_timer()
    local was_cancelled = self._cancelled
    self._running = false
    self._stop_requested = false
    self._next_iteration = nil
    if self._after then
        pcall(self._after, was_cancelled)
    end
end

function Loop:_schedule(delay)
    if not self._running then
        return
    end
    self:_close_timer()
    self._next_iteration = (luv.now and luv.now() or 0) + delay
    local timer = luv.new_timer()
    self._timer = timer
    timer:start(delay, 0, function()
        self:_run()
    end)
end

function Loop:_run()
    if not self._running then
        return
    end

    self._in_callback = true
    local ok, err = pcall(self.callback, unpack(self._args))
    self._in_callback = false
    if not self._running then
        return
    end
    if not ok then
        self._failed = true
        if self._error then
            pcall(self._error, err)
        end
        if not self.reconnect then
            self:_finish()
            return
        end
        local delay = self._backoff * 1000
        self._backoff = math.min(self._backoff * 2, self._max_backoff)
        self:_schedule(delay)
        return
    end

    self._failed = false
    self._backoff = self._initial_backoff
    self._current_loop = self._current_loop + 1

    if self._stop_requested or (self.count and self._current_loop >= self.count) then
        self:_finish()
        return
    end

    self:_schedule(self._interval)
end

function Loop:start(...)
    if self._running then
        error("tasks.loop is already running", 0)
    end

    self._args = { ... }
    self._current_loop = 0
    self._cancelled = false
    self._stop_requested = false
    self._failed = false
    self._initial_backoff = self._backoff
    self._running = true

    if self._before then
        local ok, err = pcall(self._before)
        if not ok then
            self._failed = true
            if self._error then
                pcall(self._error, err)
            end
            self:_finish()
            return self
        end
    end

    self:_schedule(0)
    return self
end

function Loop:stop()
    if self._running then
        self._stop_requested = true
        if not self._in_callback then
            self:_finish()
        end
    end
    return self
end

function Loop:cancel()
    if self._running then
        self._cancelled = true
        self:_finish()
    end
    return self
end

function Loop:call(...)
    return self.callback(...)
end

local tasks = {
    Loop = Loop,
}

function tasks.loop(callback_or_opts, maybe_opts)
    if type(callback_or_opts) == "function" then
        return Loop.new(callback_or_opts, maybe_opts)
    end
    if type(callback_or_opts) == "table" and maybe_opts == nil then
        return function(callback)
            return Loop.new(callback, callback_or_opts)
        end
    end
    error("tasks.loop expects a callback and options, or options followed by a callback", 0)
end

return tasks
