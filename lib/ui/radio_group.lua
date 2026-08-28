local class = require("../core/class")
local Item = require("./item")

local RadioGroup = class("RadioGroup", Item)

local function validate_option(option)
    if type(option) ~= "table" or option.label == nil then error("RadioGroup option requires label", 0) end
    if #tostring(option.label) > 100 then error("RadioGroup option label must be 100 characters or fewer", 0) end
    if option.value ~= nil and #tostring(option.value) > 100 then error("RadioGroup option value must be 100 characters or fewer", 0) end
    if option.description ~= nil and #tostring(option.description) > 100 then error("RadioGroup option description must be 100 characters or fewer", 0) end
end

function RadioGroup.new(opts)
    opts = opts or {}
    local self = setmetatable(Item.new("radio_group"), RadioGroup)
    if opts.custom_id ~= nil and #tostring(opts.custom_id) > 100 then error("RadioGroup custom_id must be 100 characters or fewer", 0) end
    self.custom_id = opts.custom_id or ("radio_group_" .. tostring(math.random(1, 1e9)))
    self.options = {}
    self.required = opts.required ~= false
    self.value = nil
    self.id = opts.id
    self.callback = opts.callback
    self.v2 = true
    for _, option in ipairs(opts.options or {}) do self:add_option(option) end
    return self
end

function RadioGroup:add_option(option)
    if #self.options >= 10 then error("RadioGroup can only hold 10 options", 0) end
    validate_option(option)
    self.options[#self.options + 1] = {
        label = option.label, value = option.value or option.label,
        description = option.description, default = option.default or false,
    }
    return self
end

function RadioGroup:clear_options()
    self.options = {}
    return self
end

function RadioGroup:refresh_state(data)
    self.value = data and data.value or nil
    return self
end

function RadioGroup:to_component()
    local result = { type = 21, custom_id = self.custom_id, options = self.options, required = self.required }
    if self.id ~= nil then result.id = self.id end
    return result
end

return RadioGroup
