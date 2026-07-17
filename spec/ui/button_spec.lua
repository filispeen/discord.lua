-- spec/ui/button_spec.lua
-- Tests for the Button UI component

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local Button = require("ui.button")

describe("Button", function()
    it("creates a button with defaults", function()
        local button = Button.new({ custom_id = "b1" })

        assert.equals("secondary", button.style)
        assert.equals(false, button.disabled)
        assert.is_nil(button.label)
    end)

    it("creates a labeled primary button", function()
        local button = Button.new({ label = "Click me", style = "primary", custom_id = "b1" })

        assert.equals("Click me", button.label)
        assert.equals("primary", button.style)
    end)

    it("rejects labels over 80 characters", function()
        local long_label = string.rep("a", 81)

        assert.has_error(function()
            Button.new({ label = long_label, custom_id = "b1" })
        end)
    end)

    it("rejects custom_id over 100 characters", function()
        local long_id = string.rep("a", 101)

        assert.has_error(function()
            Button.new({ label = "x", custom_id = long_id })
        end)
    end)

    it("rejects mixing url and custom_id", function()
        assert.has_error(function()
            Button.new({ label = "x", custom_id = "b1", url = "https://example.com" })
        end)
    end)

    it("requires custom_id unless style is link", function()
        assert.has_error(function()
            Button.new({ label = "x" })
        end)
    end)

    it("forces style to link when url is given", function()
        local button = Button.new({ label = "Docs", url = "https://example.com" })

        assert.equals("link", button.style)
    end)

    it("rejects invalid style", function()
        assert.has_error(function()
            Button.new({ label = "x", custom_id = "b1", style = "not_a_style" })
        end)
    end)

    it("serializes to a type 2 component with custom_id", function()
        local button = Button.new({ label = "Click me", style = "danger", custom_id = "b1" })
        local component = button:to_component()

        assert.equals(2, component.type)
        assert.equals("danger", component.style)
        assert.equals("Click me", component.label)
        assert.equals("b1", component.custom_id)
        assert.equals(false, component.disabled)
    end)

    it("serializes a link button with url instead of custom_id", function()
        local button = Button.new({ label = "Docs", url = "https://example.com" })
        local component = button:to_component()

        assert.equals("https://example.com", component.url)
        assert.is_nil(component.custom_id)
    end)

    it("respects an explicit row", function()
        local button = Button.new({ label = "x", custom_id = "b1", row = 2 })

        assert.equals(2, button.row)
    end)

    it("rejects a row outside 0..4", function()
        assert.has_error(function()
            Button.new({ label = "x", custom_id = "b1", row = 5 })
        end)
    end)
end)
