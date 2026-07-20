-- spec/ext/pages/page_group_spec.lua
-- Tests for PageGroup

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local PageGroup = require("ext.pages.page_group")

describe("PageGroup", function()
    it("requires a label", function()
        assert.has_error(function()
            PageGroup.new({ pages = { "a" } })
        end)
    end)

    it("stores pages and label", function()
        local group = PageGroup.new({ pages = { "a", "b" }, label = "Group 1" })
        assert.equals(2, #group.pages)
        assert.equals("Group 1", group.label)
    end)

    it("defaults pages to an empty table", function()
        local group = PageGroup.new({ label = "Empty" })
        assert.same({}, group.pages)
    end)

    it("defaults default_button_row to 0", function()
        local group = PageGroup.new({ label = "Group 1" })
        assert.equals(0, group.default_button_row)
    end)

    it("leaves optional overrides nil unless specified", function()
        local group = PageGroup.new({ label = "Group 1" })
        assert.is_nil(group.show_disabled)
        assert.is_nil(group.show_indicator)
        assert.is_nil(group.loop_pages)
        assert.is_nil(group.default)
    end)

    it("stores optional overrides when given", function()
        local group = PageGroup.new({
            label = "Group 1",
            description = "desc",
            default = true,
            show_disabled = false,
            show_indicator = false,
            loop_pages = true,
        })
        assert.equals("desc", group.description)
        assert.is_true(group.default)
        assert.is_false(group.show_disabled)
        assert.is_false(group.show_indicator)
        assert.is_true(group.loop_pages)
    end)
end)
