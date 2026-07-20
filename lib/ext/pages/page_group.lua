-- lib/ext/pages/page_group.lua
-- PageGroup: a named group of pages the user can switch between, contract
-- mirrors pycord discord.ext.pages.PageGroup.
--
-- Public Contract:
--   PageGroup.new(opts) -> page_group
--     opts.pages: table - list of Page/string/embed-shaped values
--     opts.label: string - shown in the PaginatorMenu dropdown, required
--     opts.description: string or nil
--     opts.default: boolean or nil - whether this is the initially shown group
--     opts.show_disabled / show_indicator / author_check / disable_on_timeout /
--       use_default_buttons / default_button_row / loop_pages / custom_view /
--       timeout / custom_buttons: same meaning as the matching Paginator option,
--       overriding it only for this group when selected. nil means "use the
--       Paginator's own setting".

local class = require("core.class")

local PageGroup = class("PageGroup")

function PageGroup.new(opts)
    opts = opts or {}

    if opts.label == nil then
        error("PageGroup requires a label", 0)
    end

    local self = setmetatable({}, PageGroup)
    self.pages = opts.pages or {}
    self.label = opts.label
    self.description = opts.description
    self.default = opts.default
    self.show_disabled = opts.show_disabled
    self.show_indicator = opts.show_indicator
    self.author_check = opts.author_check
    self.disable_on_timeout = opts.disable_on_timeout
    self.use_default_buttons = opts.use_default_buttons
    self.default_button_row = opts.default_button_row or 0
    self.loop_pages = opts.loop_pages
    self.custom_view = opts.custom_view
    self.timeout = opts.timeout
    self.custom_buttons = opts.custom_buttons

    return self
end

return PageGroup
