-- lib/ui/select.lua
-- SelectMenu component for discord.lua UI, contract mirrors pycord discord.ui.Select
--
-- Public Contract:
--   Select.new(opts) -> select
--     opts.select_type: string - one of "string", "user", "role", "channel", "mentionable". Defaults to "string".
--     opts.custom_id: string or nil - up to 100 characters, auto generated if omitted
--     opts.placeholder: string or nil
--     opts.min_values: number - defaults to 1, 0..25
--     opts.max_values: number - defaults to 1, 1..25
--     opts.options: table or nil - list of {label, value, description, emoji, default} for "string" selects
--     opts.disabled: boolean - defaults to false
--     opts.row: number or nil - 0..4
--
--   select:add_option(option) -> self
--     Appends an option table for "string" selects. Errors if more than 25 options.
--
--   select:to_component() -> table
--     Serializes to the Discord select component payload.

local class = require("core.class")
local Item = require("ui.item")

local TYPE_NUMBERS = {
    string = 3,
    user = 5,
    role = 6,
    mentionable = 7,
    channel = 8,
}

local Select = class("Select", Item)

function Select.new(opts)
    opts = opts or {}
    local self = setmetatable(Item.new("select"), Select)

    local select_type = opts.select_type or "string"
    if not TYPE_NUMBERS[select_type] then
        error("invalid select type: " .. tostring(select_type))
    end

    if opts.custom_id ~= nil and #tostring(opts.custom_id) > 100 then
        error("custom_id must be 100 characters or fewer")
    end

    local min_values = opts.min_values or 1
    local max_values = opts.max_values or 1

    if min_values < 0 or min_values > 25 then
        error("min_values must be between 0 and 25")
    end

    if max_values < 1 or max_values > 25 then
        error("max_values must be between 1 and 25")
    end

    self.select_type = select_type
    self.custom_id = opts.custom_id or ("select_" .. tostring(math.random(1, 1e9)))
    self.placeholder = opts.placeholder
    self.min_values = min_values
    self.max_values = max_values
    self.options = opts.options or {}
    self.disabled = opts.disabled or false
    self.callback = opts.callback
    self:set_row(opts.row)

    return self
end

function Select:add_option(option)
    if self.select_type ~= "string" then
        error("add_option is only valid for string selects")
    end

    if #self.options >= 25 then
        error("select menus can only hold 25 options")
    end

    table.insert(self.options, option)
    return self
end

function Select:to_component()
    local component = {
        type = TYPE_NUMBERS[self.select_type],
        custom_id = self.custom_id,
        min_values = self.min_values,
        max_values = self.max_values,
        disabled = self.disabled,
    }

    if self.placeholder ~= nil then
        component.placeholder = self.placeholder
    end

    if self.select_type == "string" then
        component.options = self.options
    end

    return component
end

return Select
