-- spec/class_test.lua
-- Tests for lib/core/class.lua

-- Setup package path to find lib modules
package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local class = require("core.class")

-- busted.describe, busted.it, busted.assert are globals when run through busted runner
describe("class.lua", function()
    -- Test basic class creation
    it("creates a new class", function()
        local MyClass = class("MyClass")
        assert.is_string(MyClass._name)
        assert.equals("MyClass", MyClass._name)
        assert.equals("table", tostring(type(MyClass)))
        assert.is_true(MyClass("instance") and type(MyClass("instance")) == "table")
    end)

    -- Test instance creation
    it("creates instances from class", function()
        local MyClass = class("MyClass")
        local instance = MyClass()
        assert.is_true(type(instance) == "table")
        assert.is_true(getmetatable(instance) == MyClass)
    end)

    -- Test inheritance
    it("supports single inheritance", function()
        local Base = class("Base")
        local Derived = class("Derived", Base)
        local derived = Derived()

        assert.is_true(class.isInstanceOf(derived, Base))
        assert.is_true(class.isInstanceOf(derived, Derived))
    end)

    -- Test isInstanceOf
    it("correctly identifies instances", function()
        local Base = class("Base")
        local Derived = class("Derived", Base)

        assert.is_true(class.isInstanceOf(Derived(), Derived))
        assert.is_true(class.isInstanceOf(Derived(), Base))
        assert.is_true(class.isInstanceOf(Base(), Base))
        assert.is_false(class.isInstanceOf(Base(), Derived))
    end)

    -- Test getName
    it("returns class name", function()
        local MyClass = class("MyClass")
        assert.equals("MyClass", class.getName(MyClass))
    end)
end)
