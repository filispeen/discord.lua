-- lib/core/class.lua
-- A minimal single-inheritance class system for discord.lua
--
-- Public Contract:
--   class(name, parent) -> class_table
--     name: string - the class name
--     parent: class_table or nil - parent class for inheritance
--     Returns: A table representing the class that can be called to create instances
--
--   instance:isInstanceOf(Class) -> boolean
--     Checks if the instance is an instance of the given class or its subclass

local M = {}

-- Create a new class with optional single inheritance
-- Uses __index metamethod chain for method resolution
function M.class(name, parent)
    local class_table = {
        _name = name,
    }

    -- Make class_table callable to create instances
    setmetatable(class_table, {
        __call = function(cls, ...)
            -- If .new() exists, call it (for constructors)
            if cls.new then
                local instance = cls.new(...)
                setmetatable(instance, cls)
                return instance
            end
            -- Otherwise create instance directly
            local instance = {}
            setmetatable(instance, cls)
            return instance
        end,
    })

    -- Set __index for method lookup - this is the class_table itself
    class_table.__index = class_table

    return class_table
end

-- Make M callable to create classes
setmetatable(M, {
    __call = function(_, name, parent)
        return M.class(name, parent)
    end
})

-- Check if an instance is of the given class (or subclass)
function M.isInstanceOf(instance, Class)
    if not Class then
        return false
    end

    local current = getmetatable(instance)
    while current do
        if current == Class then
            return true
        end
        if current._name == Class._name then
            return true
        end
        current = current.__index
    end
    return false
end

-- Get the name of a class
function M.getName(Class)
    return Class._name
end

return M
