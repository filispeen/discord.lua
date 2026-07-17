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

-- Internal storage for event subscriptions
-- Structure: { [event_name] = { fn1, fn2, ... } }
M._listeners = {}

-- Subscribe to an event
function M:on(event, fn)
    if type(fn) ~= "function" then
        error("Expected function as callback, got " .. type(fn))
    end

    if not M._listeners[event] then
        M._listeners[event] = {}
    end

    table.insert(M._listeners[event], fn)
    return self
end

-- Subscribe to an event once, then unsubscribe after first call
function M:once(event, fn)
    if type(fn) ~= "function" then
        error("Expected function as callback, got " .. type(fn))
    end

    -- Create a wrapper that removes itself after calling
    -- luacheck: ignore unused variable wrapped_fn
    local wrapped_fn = function(...)
        fn(...)
        M._listeners[event] = nil
        for _, callbacks in pairs(M._listeners) do
            for _, cb in ipairs(callbacks) do
                if cb == wrapped_fn then
                    table.remove(callbacks, #callbacks)
                    break
                end
            end
        end
    end

    M:on(event, wrapped_fn)
    return self
end

-- Emit an event to all subscribers
function M:emit(event, ...)
    if not M._listeners[event] then
        return self
    end

    -- Make a copy of callbacks to avoid modification during iteration
    local callbacks = {}
    for _, cb in ipairs(M._listeners[event]) do
        table.insert(callbacks, cb)
    end

    -- Call each callback
    for _, cb in ipairs(callbacks) do
        cb(self, ...)
    end

    -- luacheck: ignore unused argument self
    return self
end

-- Unsubscribe from an event
function M:off(event, fn)
    if not M._listeners[event] then
        return self
    end

    if not fn then
        -- Remove all listeners for this event
        M._listeners[event] = nil
    else
        -- Remove specific listener
        for i, cb in ipairs(M._listeners[event]) do
            if cb == fn then
                table.remove(M._listeners[event], i)
                break
            end
        end
    end

    return self
end

-- Get all listeners for an event (for debugging)
function M.getListeners(_self, event)
    return M._listeners[event] or {}
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
