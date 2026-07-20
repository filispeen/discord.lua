-- lib/ext/pages/page.lua
-- Page: represents a single page shown in the Paginator, contract mirrors
-- pycord discord.ext.pages.Page.
--
-- Public Contract:
--   Page.new(opts) -> page
--     opts.content: string or nil - message content
--     opts.embeds: table or nil - a single embed or list of embeds
--     opts.custom_view: View or nil - overrides the Paginator's own view when shown
--     opts.callback: function(interaction) or nil, invoked by Paginator:page_action()
--     At least one of content, embeds, or custom_view is required.
--
--   page.content / page.embeds / page.custom_view -> as above, directly readable/writable
--
--   Page.from_value(value) -> page
--     Converts a raw value (string, Embed-like table, list of embeds, an
--     already-built Page, or a View) into a Page, mirrors pycord's static
--     Paginator.get_page_content. Errors on an unrecognized type.

local class = require("core.class")

local Page = class("Page")

function Page.new(opts)
    opts = opts or {}

    if opts.content == nil and opts.embeds == nil and opts.custom_view == nil then
        error("a Page must have at least content, embeds, or custom_view set", 0)
    end

    local self = setmetatable({}, Page)
    self.content = opts.content
    self.embeds = opts.embeds or {}
    self.custom_view = opts.custom_view
    self.callback = opts.callback

    return self
end

-- Returns true if value looks like a single Embed-shaped table (has a
-- title, description, or fields field), rather than a list of embeds.
local function is_embed_like(value)
    return type(value) == "table"
        and (value.title ~= nil or value.description ~= nil or value.fields ~= nil)
        and value[1] == nil
end

function Page.from_value(value)
    if class.isInstanceOf(value, Page) then
        return value
    end

    if type(value) == "string" then
        return Page.new({ content = value })
    end

    if is_embed_like(value) then
        return Page.new({ embeds = { value } })
    end

    if type(value) == "table" then
        -- Either a list of embeds, or (heuristically) a View: a View has
        -- an "items" field and no embed-shaped fields.
        if value.items ~= nil and value.title == nil then
            return Page.new({ custom_view = value })
        end
        return Page.new({ embeds = value })
    end

    error("Page content must be a Page, string, embed, list of embeds, or View", 0)
end

return Page
