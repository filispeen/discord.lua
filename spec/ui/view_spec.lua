-- spec/ui/view_spec.lua
-- Tests for the View container

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local View = require("ui.view")
local Button = require("ui.button")

local function make_button(id)
    return Button.new({ label = id, custom_id = id })
end

describe("View", function()
    it("creates a view with no items", function()
        local view = View.new()

        assert.equals(0, #view.items)
        assert.equals(false, view.stopped)
    end)

    it("stores a timeout in milliseconds", function()
        local view = View.new({ timeout = 30000 })

        assert.equals(30000, view.timeout_ms)
    end)

    it("adds an item and assigns row automatically", function()
        local view = View.new()
        local button = make_button("b1")
        view:add(button)

        assert.equals(1, #view.items)
        assert.equals(0, button.row)
    end)

    it("packs up to 5 items per row before moving to the next", function()
        local view = View.new()
        for i = 1, 5 do
            view:add(make_button("b" .. i))
        end
        local overflow = make_button("b6")
        view:add(overflow)

        assert.equals(1, overflow.row)
    end)

    it("errors when all 5 rows are full", function()
        local view = View.new()
        for i = 1, 25 do
            view:add(make_button("b" .. i))
        end

        assert.has_error(function()
            view:add(make_button("overflow"))
        end)
    end)

    it("respects an explicit row on the item", function()
        local view = View.new()
        local button = make_button("b1")
        button.row = 3
        view:add(button)

        assert.equals(3, button.row)
    end)

    it("removes an item by reference", function()
        local view = View.new()
        local button = make_button("b1")
        view:add(button)
        view:remove(button)

        assert.equals(0, #view.items)
    end)

    it("removes an item by custom_id", function()
        local view = View.new()
        view:add(make_button("b1"))
        view:remove("b1")

        assert.equals(0, #view.items)
    end)

    it("clears all items", function()
        local view = View.new()
        view:add(make_button("b1"))
        view:add(make_button("b2"))
        view:clear()

        assert.equals(0, #view.items)
    end)

    it("updates the timeout", function()
        local view = View.new()
        view:timeout(60000)

        assert.equals(60000, view.timeout_ms)
    end)

    it("serializes items grouped into action rows", function()
        local view = View.new()
        view:add(make_button("b1"))
        local components = view:to_components()

        assert.equals(1, #components)
        assert.equals(1, components[1].type)
        assert.equals(1, #components[1].components)
    end)

    it("produces separate action rows for explicit rows", function()
        local view = View.new()
        local b1 = make_button("b1")
        b1.row = 0
        local b2 = make_button("b2")
        b2.row = 1
        view:add(b1)
        view:add(b2)

        local components = view:to_components()

        assert.equals(2, #components)
    end)

    it("marks the view as stopped", function()
        local view = View.new()
        view:stop()

        assert.equals(true, view.stopped)
    end)

    it("sets view reference on attached items", function()
        local view = View.new()
        local button = make_button("b1")
        view:add(button)

        assert.equals(view, button.view)
    end)

    it("finds an attached item by custom_id", function()
        local view = View.new()
        local button = make_button("b1")
        view:add(button)

        assert.equals(button, view:find_item("b1"))
        assert.is_nil(view:find_item("missing"))
    end)
end)
