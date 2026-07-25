-- lib/core/emitter.lua
-- An event emitter for discord.lua
--
-- Public Contract:
--   emitter:on(event, fn) -> self
--     Subscribe to an event. Called with emitter as first argument.
--     event: string - the event name
--     fn: function - the callback function
--     Returns: self for method chaining
--
--   emitter:once(event, fn) -> self
--     Subscribe to an event once, then automatically unsubscribe.
--     event: string - the event name
--     fn: function - the callback function
--     Returns: self for method chaining
--
--   emitter:emit(event, ...) -> self
--     Emit an event, calling all subscribers in FIFO order.
--     event: string - the event name
--     ...: any - additional arguments passed to subscribers
--     Returns: self for method chaining
--
--   emitter:off(event, fn) -> self
--     Unsubscribe from an event.
--     event: string - the event name
--     fn: function or nil - specific function to remove, or nil to remove all
--     Returns: self for method chaining
--
--   emitter:getListeners(event) -> table
--     Get all subscribers for an event (useful for debugging).
--     event: string - the event name
--     Returns: table of callback functions

local M = {}

-- Subscribe to an event
function M:on(event, fn)
    if type(fn) ~= "function" then
        error("Expected function as callback, got " .. type(fn))
    end

    if not self._listeners[event] then
        self._listeners[event] = {}
    end

    table.insert(self._listeners[event], fn)
    return self
end

-- Subscribe to an event once, then unsubscribe after first call
function M:once(event, fn)
    if type(fn) ~= "function" then
        error("Expected function as callback, got " .. type(fn))
    end

    local wrapped_fn
    wrapped_fn = function(...)
        self:off(event, wrapped_fn)
        fn(...)
    end

    self:on(event, wrapped_fn)
    return self
end

-- Emit an event to all subscribers
function M:emit(event, ...)
    if not self._listeners[event] then
        return self
    end

    -- Make a copy of callbacks to avoid modification during iteration
    local callbacks = {}
    for _, cb in ipairs(self._listeners[event]) do
        table.insert(callbacks, cb)
    end

    -- Call each callback
    for _, cb in ipairs(callbacks) do
        cb(self, ...)
    end

    return self
end

-- Unsubscribe from an event
function M:off(event, fn)
    if not self._listeners[event] then
        return self
    end

    if not fn then
        -- Remove all listeners for this event
        self._listeners[event] = nil
    else
        -- Remove specific listener
        for i, cb in ipairs(self._listeners[event]) do
            if cb == fn then
                table.remove(self._listeners[event], i)
                break
            end
        end
    end

    return self
end

-- Get all listeners for an event (for debugging)
function M.getListeners(self, event)
    return self._listeners[event] or {}
end

-- Make M callable to create an emitter
setmetatable(M, {
    __call = function()
        local instance = {
            _listeners = {}
        }
        instance.on = M.on
        instance.once = M.once
        instance.emit = M.emit
        instance.off = M.off
        instance.getListeners = M.getListeners
        return instance
    end
})

return M
