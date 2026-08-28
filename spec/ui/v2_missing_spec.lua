require("spec_helper")

local ActionRow = require("./ui/action_row")
local Button = require("./ui/button")
local Select = require("./ui/select")
local InputText = require("./ui/input_text")
local Checkbox = require("./ui/checkbox")
local CheckboxGroup = require("./ui/checkbox_group")
local RadioGroup = require("./ui/radio_group")
local File = require("./ui/file")
local Modal = require("./ui/modal")
local View = require("./ui/view")

describe("UI V2 missing components", function()
    it("serializes an explicit action row and enforces its width", function()
        local row = ActionRow.new({ id = 7 })
        for index = 1, 5 do row:add_item(Button.new({ custom_id = "b" .. index })) end

        local component = row:to_component()

        assert.equals(1, component.type)
        assert.equals(7, component.id)
        assert.equals(5, #component.components)
        assert.has_error(function() row:add_item(Button.new({ custom_id = "overflow" })) end)
        assert.has_error(function() row:add_item(Select.new({ custom_id = "pick" })) end)
    end)

    it("keeps explicit action rows intact in a view", function()
        local view = View.new()
        local row = ActionRow.new({ items = { Button.new({ custom_id = "b1" }) } })
        view:add(row)

        local components = view:to_components()

        assert.equals(1, #components)
        assert.equals(1, components[1].type)
        assert.equals("b1", components[1].components[1].custom_id)
    end)

    it("serializes InputText through a legacy modal action row and refreshes value", function()
        local input = InputText.new({
            custom_id = "reason", label = "Reason", style = "paragraph",
            min_length = 2, max_length = 100, placeholder = "Explain",
        })
        local modal = Modal.new({ title = "Feedback", custom_id = "feedback" })
        modal:add_item(input)
        input:refresh_state({ value = "Great" })

        local payload = modal:to_component()

        assert.equals(1, payload.components[1].type)
        assert.equals(4, payload.components[1].components[1].type)
        assert.equals(2, payload.components[1].components[1].style)
        assert.equals("Great", input.value)
    end)

    it("serializes checkbox controls as direct V2 modal components", function()
        local checkbox = Checkbox.new({ custom_id = "terms", default = true, id = 1 })
        local group = CheckboxGroup.new({
            custom_id = "topics", min_values = 1, max_values = 2,
            options = { { label = "Lua", value = "lua", description = "Language" } },
        })
        local radio = RadioGroup.new({
            custom_id = "plan",
            options = { { label = "Free" }, { label = "Pro", default = true } },
        })
        local modal = Modal.new({ title = "Settings" })
        modal:add_item(checkbox):add_item(group):add_item(radio)
        checkbox:refresh_state({ value = false })
        group:refresh_state({ values = { "lua" } })
        radio:refresh_state({ value = "Pro" })

        local payload = modal:to_component()

        assert.equals(23, payload.components[1].type)
        assert.equals(22, payload.components[2].type)
        assert.equals(21, payload.components[3].type)
        assert.is_false(checkbox.value)
        assert.same({ "lua" }, group.values)
        assert.equals("Pro", radio.value)
        assert.has_error(function()
            for index = 1, 11 do group:add_option({ label = "Option " .. index }) end
        end)
    end)

    it("serializes the UI File component as type 13", function()
        local file = File.new({ url = "attachment://report.pdf", spoiler = true, id = 9 })
        local component = file:to_component()

        assert.equals(13, component.type)
        assert.equals("attachment://report.pdf", component.file.url)
        assert.is_true(component.spoiler)
        assert.equals(9, component.id)
    end)
end)
