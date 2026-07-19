-- spec/ui/text_display_spec.lua
-- Tests for the TextDisplay UI component (Components V2)

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local TextDisplay = require("ui.text_display")

describe("TextDisplay", function()
    it("creates a text display with content", function()
        local text_display = TextDisplay.new("Hello world")
        assert.equals("Hello world", text_display.content)
    end)

    it("requires content", function()
        assert.has_error(function()
            TextDisplay.new(nil)
        end)
    end)

    it("rejects content over 4000 characters", function()
        local long_content = string.rep("a", 4001)
        assert.has_error(function()
            TextDisplay.new(long_content)
        end)
    end)

    it("serializes to a type 10 component", function()
        local text_display = TextDisplay.new("Hello world")
        local component = text_display:to_component()

        assert.equals(10, component.type)
        assert.equals("Hello world", component.content)
    end)
end)
