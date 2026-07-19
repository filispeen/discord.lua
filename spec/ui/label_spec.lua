-- spec/ui/label_spec.lua
-- Tests for the Label UI component (Components V2)

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local Label = require("ui.label")

-- Minimal stand-in for a wrapped input component (InputText/Select/FileUpload)
local function fake_component(payload)
    return {
        to_component = function() return payload end,
    }
end

describe("Label", function()
    it("creates a label wrapping a component", function()
        local input = fake_component({ type = 4, custom_id = "name" })
        local label = Label.new({ text = "Your name", component = input })

        assert.equals("Your name", label.text)
        assert.equals(input, label.component)
    end)

    it("requires text", function()
        assert.has_error(function()
            Label.new({ component = fake_component({}) })
        end)
    end)

    it("rejects text over 45 characters", function()
        assert.has_error(function()
            Label.new({ text = string.rep("a", 46), component = fake_component({}) })
        end)
    end)

    it("rejects description over 100 characters", function()
        assert.has_error(function()
            Label.new({
                text = "Name",
                description = string.rep("a", 101),
                component = fake_component({}),
            })
        end)
    end)

    it("requires a component", function()
        assert.has_error(function()
            Label.new({ text = "Name" })
        end)
    end)

    it("serializes to a type 18 component wrapping the rendered child", function()
        local input = fake_component({ type = 4, custom_id = "name" })
        local label = Label.new({ text = "Your name", description = "Full legal name", component = input })
        local component = label:to_component()

        assert.equals(18, component.type)
        assert.equals("Your name", component.label)
        assert.equals("Full legal name", component.description)
        assert.equals(4, component.component.type)
        assert.equals("name", component.component.custom_id)
    end)
end)
