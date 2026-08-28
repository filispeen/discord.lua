local class = require("../core/class")
local Item = require("./item")

local Checkbox = class("Checkbox", Item)

function Checkbox.new(opts)
    opts = opts or {}
    local self = setmetatable(Item.new("checkbox"), Checkbox)
    if opts.custom_id ~= nil and #tostring(opts.custom_id) > 100 then error("Checkbox custom_id must be 100 characters or fewer", 0) end
    self.custom_id = opts.custom_id or ("checkbox_" .. tostring(math.random(1, 1e9)))
    self.default = opts.default or false
    self.value = nil
    self.id = opts.id
    self.callback = opts.callback
    self.v2 = true
    return self
end

function Checkbox:refresh_state(data)
    if data then self.value = data.value else self.value = nil end
    return self
end

function Checkbox:to_component()
    local result = { type = 23, custom_id = self.custom_id, default = self.default }
    if self.id ~= nil then result.id = self.id end
    return result
end

return Checkbox
