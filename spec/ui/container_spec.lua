-- spec/ui/container_spec.lua
-- Tests for the Container UI component (Components V2)

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local Container = require("ui.container")
local TextDisplay = require("ui.text_display")
local Separator = require("ui.separator")

describe("Container", function()
    it("creates a container with child components", function()
        local container = Container.new({
            components = { TextDisplay.new("Hello") },
        })
        assert.equals(1, #container.components)
        assert.is_false(container.spoiler)
    end)

    it("defaults to an empty component list", function()
        local container = Container.new()
        assert.equals(0, #container.components)
    end)

    it("add_item appends a child component", function()
        local container = Container.new()
        container:add_item(TextDisplay.new("Hello"))
        container:add_item(Separator.new())
        assert.equals(2, #container.components)
    end)

    it("serializes to a type 17 component with rendered children", function()
        local container = Container.new({
            components = { TextDisplay.new("Hello"), Separator.new() },
            accent_color = 0xFF0000,
            spoiler = true,
        })
        local component = container:to_component()

        assert.equals(17, component.type)
        assert.equals(2, #component.components)
        assert.equals(10, component.components[1].type)
        assert.equals(14, component.components[2].type)
        assert.equals(0xFF0000, component.accent_color)
        assert.is_true(component.spoiler)
    end)

    it("omits accent_color from the payload when not set", function()
        local container = Container.new({ components = { TextDisplay.new("Hello") } })
        local component = container:to_component()

        assert.is_nil(component.accent_color)
    end)
end)
