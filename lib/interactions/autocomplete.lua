-- lib/interactions/autocomplete.lua
-- Autocomplete helpers, contract mirrors pycord discord.utils.basic_autocomplete.
--
-- Public Contract:
--   M.basic_autocomplete(source) -> callback(ctx) -> table
--     source: table (a static list of choices) or function(ctx) -> table
--     Returns a callback suitable for ApplicationCommand:set_autocomplete,
--     built from either a static list or a callback. If source is a
--     callback, it is invoked with the AutocompleteContext (ctx.value,
--     ctx.options) so it can filter by whatever the user has typed so far.
--     The result is filtered case-insensitively against ctx.value and
--     capped at 25 items, matching Discord's autocomplete choice limit.

local M = {}

local function filter_by_value(list, value)
    if not value or value == "" then
        return list
    end

    local needle = tostring(value):lower()
    local filtered = {}
    for _, item in ipairs(list) do
        local text = type(item) == "table" and (item.name or item.label) or tostring(item)
        if tostring(text):lower():find(needle, 1, true) then
            table.insert(filtered, item)
        end
    end
    return filtered
end

local function cap(list, max_items)
    if #list <= max_items then
        return list
    end
    local capped = {}
    for i = 1, max_items do
        capped[i] = list[i]
    end
    return capped
end

function M.basic_autocomplete(source)
    return function(ctx)
        local list
        if type(source) == "function" then
            list = source(ctx) or {}
        else
            list = source or {}
        end

        local filtered = filter_by_value(list, ctx.value)
        return cap(filtered, 25)
    end
end

return M
