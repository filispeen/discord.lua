-- spec/ext/pages/paginator_button_spec.lua
-- Tests for PaginatorButton

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local PaginatorButton = require("ext.pages.paginator_button")

describe("PaginatorButton", function()
    it("errors on an invalid button type", function()
        assert.has_error(function()
            PaginatorButton.new("teleport")
        end)
    end)

    it("defaults label to a capitalized button_type when no emoji is given", function()
        local button = PaginatorButton.new("first")
        assert.equals("First", button.label)
    end)

    it("leaves label nil when only an emoji is given", function()
        local button = PaginatorButton.new("first", { emoji = "⏮️" })
        assert.is_nil(button.label)
        assert.equals("⏮️", button.emoji)
    end)

    it("defaults style to success", function()
        local button = PaginatorButton.new("next")
        assert.equals("success", button.style)
    end)

    it("defaults disabled to false and row to 0", function()
        local button = PaginatorButton.new("next")
        assert.is_false(button.disabled)
        assert.equals(0, button.row)
    end)

    it("defaults loop_label to the button's label", function()
        local button = PaginatorButton.new("next", { label = "Next" })
        assert.equals("Next", button.loop_label)
    end)

    it("accepts an explicit loop_label", function()
        local button = PaginatorButton.new("next", { label = "Next", loop_label = "Loop" })
        assert.equals("Loop", button.loop_label)
    end)

    it("accepts custom_id, style, row overrides", function()
        local button = PaginatorButton.new("page_indicator", {
            custom_id = "my_indicator",
            style = "secondary",
            row = 2,
        })
        assert.equals("my_indicator", button.custom_id)
        assert.equals("secondary", button.style)
        assert.equals(2, button.row)
    end)
end)
