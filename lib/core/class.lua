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
        __call = function(self, ...)
            -- Create instance with self as metatable
            local instance = {}
            setmetatable(instance, self)
            return instance
        end,
    })

    -- Set __index AFTER __call is set, so __call is checked first
    -- parent is already the class_table (not parent.class_table)
    class_table.__index = parent and parent or M
    return class_table
end

-- Make M callable to create classes
-- The __call metatable receives M as self, so we need to handle this
setmetatable(M, {
    __call = function(self, name, parent)
        return M.class(name, parent)
    end
})

-- Check if an instance is of the given class (or subclass)
-- Traverses the __index chain to find the class_table
function M.isInstanceOf(instance, Class)
    if not Class then
        return false
    end

    local current = getmetatable(instance)
    while current do
        -- Check if current is the Class itself (for direct class references)
        if current == Class then
            return true
        end
        -- Check if current has the __name field matching Class._name
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
