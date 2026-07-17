-- spec/ui/modal_spec.lua
-- Tests for the Modal component

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local Modal = require("ui.modal")

describe("Modal", function()
    it("creates a modal with a title", function()
        local modal = Modal.new({ title = "Feedback" })

        assert.equals("Feedback", modal.title)
        assert.equals(0, #modal.items)
        assert.equals(false, modal.stopped)
    end)

    it("requires a title", function()
        assert.has_error(function()
            Modal.new({})
        end)
    end)

    it("rejects a title over 45 characters", function()
        assert.has_error(function()
            Modal.new({ title = string.rep("a", 46) })
        end)
    end)

    it("rejects a custom_id over 100 characters", function()
        assert.has_error(function()
            Modal.new({ title = "Feedback", custom_id = string.rep("a", 101) })
        end)
    end)

    it("generates a custom_id when none is given", function()
        local modal = Modal.new({ title = "Feedback" })

        assert.is_not_nil(modal.custom_id)
    end)

    it("uses a provided custom_id", function()
        local modal = Modal.new({ title = "Feedback", custom_id = "fb1" })

        assert.equals("fb1", modal.custom_id)
    end)

    it("adds an item", function()
        local modal = Modal.new({ title = "Feedback" })
        modal:add_item({ to_component = function() return { type = 4 } end })

        assert.equals(1, #modal.items)
    end)

    it("rejects more than 5 items", function()
        local modal = Modal.new({ title = "Feedback" })
        for _ = 1, 5 do
            modal:add_item({ to_component = function() return { type = 4 } end })
        end

        assert.has_error(function()
            modal:add_item({ to_component = function() return { type = 4 } end })
        end)
    end)

    it("serializes to a payload with title, custom_id and rows", function()
        local modal = Modal.new({ title = "Feedback", custom_id = "fb1" })
        modal:add_item({ to_component = function() return { type = 4, custom_id = "field1" } end })

        local payload = modal:to_component()

        assert.equals("Feedback", payload.title)
        assert.equals("fb1", payload.custom_id)
        assert.equals(1, #payload.components)
        assert.equals(1, payload.components[1].type)
    end)

    it("marks the modal as stopped", function()
        local modal = Modal.new({ title = "Feedback" })
        modal:stop()

        assert.equals(true, modal.stopped)
    end)
end)
