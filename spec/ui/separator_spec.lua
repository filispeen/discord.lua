-- spec/ui/separator_spec.lua
-- Tests for the Separator UI component (Components V2)

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local Separator = require("ui.separator")

describe("Separator", function()
    it("defaults to a visible small divider", function()
        local separator = Separator.new()
        assert.is_true(separator.divider)
        assert.equals("small", separator.spacing)
    end)

    it("accepts divider = false and spacing = large", function()
        local separator = Separator.new({ divider = false, spacing = "large" })
        assert.is_false(separator.divider)
        assert.equals("large", separator.spacing)
    end)

    it("rejects an invalid spacing value", function()
        assert.has_error(function()
            Separator.new({ spacing = "medium" })
        end)
    end)

    it("serializes to a type 14 component with numeric spacing", function()
        local separator = Separator.new({ spacing = "large" })
        local component = separator:to_component()

        assert.equals(14, component.type)
        assert.is_true(component.divider)
        assert.equals(2, component.spacing)
    end)
end)
