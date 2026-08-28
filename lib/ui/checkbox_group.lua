local class = require("../core/class")
local Item = require("./item")

local CheckboxGroup = class("CheckboxGroup", Item)

local function validate_option(option)
    if type(option) ~= "table" or option.label == nil then error("CheckboxGroup option requires label", 0) end
    if #tostring(option.label) > 100 then error("CheckboxGroup option label must be 100 characters or fewer", 0) end
    if option.value ~= nil and #tostring(option.value) > 100 then error("CheckboxGroup option value must be 100 characters or fewer", 0) end
    if option.description ~= nil and #tostring(option.description) > 100 then error("CheckboxGroup option description must be 100 characters or fewer", 0) end
end

function CheckboxGroup.new(opts)
    opts = opts or {}
    local self = setmetatable(Item.new("checkbox_group"), CheckboxGroup)
    if opts.custom_id ~= nil and #tostring(opts.custom_id) > 100 then error("CheckboxGroup custom_id must be 100 characters or fewer", 0) end
    self.custom_id = opts.custom_id or ("checkbox_group_" .. tostring(math.random(1, 1e9)))
    self.options = {}
    self.min_values = opts.min_values
    self.max_values = opts.max_values
    if self.min_values ~= nil and (self.min_values < 0 or self.min_values > 10) then error("CheckboxGroup min_values must be between 0 and 10", 0) end
    if self.max_values ~= nil and (self.max_values < 1 or self.max_values > 10) then error("CheckboxGroup max_values must be between 1 and 10", 0) end
    self.required = opts.required ~= false
    self.values = nil
    self.id = opts.id
    self.callback = opts.callback
    self.v2 = true
    for _, option in ipairs(opts.options or {}) do self:add_option(option) end
    return self
end

function CheckboxGroup:add_option(option)
    if #self.options >= 10 then error("CheckboxGroup can only hold 10 options", 0) end
    validate_option(option)
    self.options[#self.options + 1] = {
        label = option.label, value = option.value or option.label,
        description = option.description, default = option.default or false,
    }
    return self
end

function CheckboxGroup:clear_options()
    self.options = {}
    return self
end

function CheckboxGroup:refresh_state(data)
    self.values = data and data.values or {}
    return self
end

function CheckboxGroup:to_component()
    local result = { type = 22, custom_id = self.custom_id, options = self.options, required = self.required }
    if self.min_values ~= nil then result.min_values = self.min_values end
    if self.max_values ~= nil then result.max_values = self.max_values end
    if self.id ~= nil then result.id = self.id end
    return result
end

return CheckboxGroup
