-- spec/ui/select_spec.lua
-- Tests for the Select UI component

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local Select = require("ui.select")

describe("Select", function()
    it("creates a string select with defaults", function()
        local select = Select.new({ custom_id = "s1" })

        assert.equals("string", select.select_type)
        assert.equals(1, select.min_values)
        assert.equals(1, select.max_values)
        assert.equals(0, #select.options)
    end)

    it("generates a custom_id when none is given", function()
        local select = Select.new({})

        assert.is_not_nil(select.custom_id)
    end)

    it("rejects an invalid select_type", function()
        assert.has_error(function()
            Select.new({ select_type = "not_a_type" })
        end)
    end)

    it("rejects min_values above 25", function()
        assert.has_error(function()
            Select.new({ custom_id = "s1", min_values = 26 })
        end)
    end)

    it("rejects max_values below 1", function()
        assert.has_error(function()
            Select.new({ custom_id = "s1", max_values = 0 })
        end)
    end)

    it("adds an option to a string select", function()
        local select = Select.new({ custom_id = "s1" })
        select:add_option({ label = "Option A", value = "a" })

        assert.equals(1, #select.options)
        assert.equals("Option A", select.options[1].label)
    end)

    it("rejects add_option on a non string select", function()
        local select = Select.new({ custom_id = "s1", select_type = "user" })

        assert.has_error(function()
            select:add_option({ label = "x", value = "x" })
        end)
    end)

    it("rejects more than 25 options", function()
        local select = Select.new({ custom_id = "s1" })
        for i = 1, 25 do
            select:add_option({ label = "opt" .. i, value = "v" .. i })
        end

        assert.has_error(function()
            select:add_option({ label = "overflow", value = "overflow" })
        end)
    end)

    it("serializes a string select with the correct type number", function()
        local select = Select.new({ custom_id = "s1", placeholder = "Pick one" })
        select:add_option({ label = "a", value = "a" })
        local component = select:to_component()

        assert.equals(3, component.type)
        assert.equals("s1", component.custom_id)
        assert.equals("Pick one", component.placeholder)
        assert.equals(1, #component.options)
    end)

    it("serializes a user select without an options field", function()
        local select = Select.new({ custom_id = "s1", select_type = "user" })
        local component = select:to_component()

        assert.equals(5, component.type)
        assert.is_nil(component.options)
    end)

    it("serializes a role select with the correct type number", function()
        local select = Select.new({ custom_id = "s1", select_type = "role" })
        assert.equals(6, select:to_component().type)
    end)

    it("serializes a channel select with the correct type number", function()
        local select = Select.new({ custom_id = "s1", select_type = "channel" })
        assert.equals(8, select:to_component().type)
    end)
end)
