local class = require("../core/class")
local Item = require("./item")

local InputText = class("InputText", Item)

function InputText.new(opts)
    opts = opts or {}
    local self = setmetatable(Item.new("input_text"), InputText)
    local style = opts.style or "short"
    if style == "short" then style = 1 elseif style == "paragraph" or style == "long" then style = 2 end
    if style ~= 1 and style ~= 2 then error("InputText style must be short or paragraph", 0) end
    if opts.label ~= nil and #tostring(opts.label) > 45 then error("InputText label must be 45 characters or fewer", 0) end
    if opts.placeholder ~= nil and #tostring(opts.placeholder) > 100 then error("InputText placeholder must be 100 characters or fewer", 0) end
    if opts.custom_id ~= nil and #tostring(opts.custom_id) > 100 then error("InputText custom_id must be 100 characters or fewer", 0) end
    local min_length, max_length = opts.min_length, opts.max_length
    if min_length ~= nil and (min_length < 0 or min_length > 4000) then error("InputText min_length must be between 0 and 4000", 0) end
    if max_length ~= nil and (max_length < 1 or max_length > 4000) then error("InputText max_length must be between 1 and 4000", 0) end
    if min_length and max_length and min_length > max_length then error("InputText min_length cannot exceed max_length", 0) end
    if opts.value ~= nil and #tostring(opts.value) > 4000 then error("InputText value must be 4000 characters or fewer", 0) end
    self.style = style
    self.custom_id = opts.custom_id or ("input_" .. tostring(math.random(1, 1e9)))
    self.label = opts.label
    self.placeholder = opts.placeholder
    self.min_length = min_length
    self.max_length = max_length
    self.required = opts.required ~= false
    self.value = opts.value
    self.id = opts.id
    self.callback = opts.callback
    self.width = 5
    self:set_row(opts.row)
    return self
end

function InputText:refresh_state(data)
    self.value = data and data.value or nil
    return self
end

function InputText:to_component()
    local result = {
        type = 4, style = self.style, custom_id = self.custom_id,
        required = self.required,
    }
    if self.label ~= nil then result.label = self.label end
    if self.placeholder ~= nil then result.placeholder = self.placeholder end
    if self.min_length ~= nil then result.min_length = self.min_length end
    if self.max_length ~= nil then result.max_length = self.max_length end
    if self.value ~= nil then result.value = self.value end
    if self.id ~= nil then result.id = self.id end
    return result
end

return InputText
