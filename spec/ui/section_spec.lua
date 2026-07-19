-- spec/ui/section_spec.lua
-- Tests for the Section UI component (Components V2)

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local Section = require("ui.section")
local TextDisplay = require("ui.text_display")
local Thumbnail = require("ui.thumbnail")

describe("Section", function()
    it("creates a section with text displays and an accessory", function()
        local section = Section.new({
            components = { TextDisplay.new("Hello") },
            accessory = Thumbnail.new({ url = "attachment://a.png" }),
        })
        assert.equals(1, #section.components)
    end)

    it("requires at least 1 component", function()
        assert.has_error(function()
            Section.new({ components = {}, accessory = Thumbnail.new({ url = "attachment://a.png" }) })
        end)
    end)

    it("rejects more than 3 components", function()
        local components = {
            TextDisplay.new("one"),
            TextDisplay.new("two"),
            TextDisplay.new("three"),
            TextDisplay.new("four"),
        }
        assert.has_error(function()
            Section.new({ components = components, accessory = Thumbnail.new({ url = "attachment://a.png" }) })
        end)
    end)

    it("requires an accessory", function()
        assert.has_error(function()
            Section.new({ components = { TextDisplay.new("Hello") } })
        end)
    end)

    it("serializes to a type 9 component with rendered children and accessory", function()
        local section = Section.new({
            components = { TextDisplay.new("Hello") },
            accessory = Thumbnail.new({ url = "attachment://a.png" }),
        })
        local component = section:to_component()

        assert.equals(9, component.type)
        assert.equals(1, #component.components)
        assert.equals(10, component.components[1].type)
        assert.equals(11, component.accessory.type)
    end)
end)
