-- lib/ext/pages/paginator.lua
-- Paginator: a View subclass for sending paginated content, contract
-- mirrors pycord discord.ext.pages.Paginator. This codebase is synchronous
-- (Luvit callbacks, not async/await), so respond/edit/disable/cancel return
-- the REST call's result directly instead of awaiting a coroutine, and
-- button/menu callbacks are invoked synchronously by dispatch, same as
-- every other UI item in lib/ui/.
--
-- Public Contract:
--   Paginator.new(opts) -> paginator
--     opts.pages: array of Page/PageGroup/string/embed-shaped values, required
--     opts.show_disabled: boolean, defaults to true
--     opts.show_indicator: boolean, defaults to true
--     opts.show_menu: boolean, defaults to false (only meaningful if opts.pages is PageGroups)
--     opts.menu_placeholder: string, defaults to "Select Page Group"
--     opts.author_check: boolean, defaults to true
--     opts.disable_on_timeout: boolean, defaults to true
--     opts.use_default_buttons: boolean, defaults to true
--     opts.default_button_row: number, defaults to 0
--     opts.loop_pages: boolean, defaults to false
--     opts.custom_view: View or nil, items appended below pagination buttons
--     opts.timeout: number or nil, milliseconds, defaults to 180000 (matches View)
--     opts.custom_buttons: array of PaginatorButton, ignored if use_default_buttons is true
--
--   paginator.current_page -> number, zero-indexed
--   paginator.page_count -> number, zero-indexed (last valid page index)
--
--   paginator:add_button(button) -> self
--   paginator:remove_button(button_type) -> self
--   paginator:update_buttons() -> self
--     Recomputes hidden/disabled state and rebuilds the view's item list.
--
--   paginator:goto_page(page_number) -> Page
--     Updates current_page, rebuilds buttons, and returns the resolved Page
--     for the caller to actually send/edit with (this library has no
--     stored message/interaction handle to auto-edit, unlike pycord).
--
--   paginator:respond(ctx, opts) -> result
--     ctx: a SlashCommandContext (has :respond). opts.ephemeral: boolean.
--     Sends the current page as the interaction response, with this
--     paginator's components attached.
--
--   paginator:edit(ctx, opts) -> result
--     Edits the existing interaction response to show the current page.
--
--   paginator:disable(page) -> table
--     Disables every navigational button. page, if given, replaces the
--     content/embeds shown (same shapes Page.from_value accepts).
--     Returns the render payload {content, embeds, components}; caller
--     is responsible for actually editing the message/interaction with it.
--
--   paginator:cancel(page) -> table
--     Same as disable, but removes the buttons entirely instead of
--     disabling them.
--
--   paginator:page_action() -> nil
--     Invokes the current page's callback, if any.

local class = require("core.class")
local View = require("ui.view")
local Button = require("ui.button")
local Select = require("ui.select")
local Page = require("ext.pages.page")
local PageGroup = require("ext.pages.page_group")
local PaginatorButton = require("ext.pages.paginator_button")

local Paginator = class("Paginator", View)

local function resolve_pages(pages)
    local resolved = {}
    for i, page in ipairs(pages) do
        resolved[i] = Page.from_value(page)
    end
    return resolved
end

local function is_page_group_list(pages)
    if #pages == 0 then
        return false
    end
    for _, page in ipairs(pages) do
        if not class.isInstanceOf(page, PageGroup) then
            return false
        end
    end
    return true
end

function Paginator.new(opts)
    opts = opts or {}
    if opts.pages == nil then
        error("Paginator requires pages", 0)
    end

    local timeout = opts.timeout
    if timeout == nil then
        timeout = 180000
    end

    local self = setmetatable(View.new({ timeout = timeout }), Paginator)

    self.current_page = 0
    self.show_menu = opts.show_menu or false
    self.menu_placeholder = opts.menu_placeholder or "Select Page Group"
    self.page_groups = nil

    local pages = opts.pages
    if is_page_group_list(pages) then
        local default_count = 0
        local default_index = 1
        for i, group in ipairs(pages) do
            if group.default then
                default_count = default_count + 1
                default_index = i
            end
        end
        if default_count > 1 then
            error("Only one PageGroup can be set as the default.", 0)
        end

        self.page_groups = self.show_menu and pages or nil
        self.pages = resolve_pages(pages[default_index].pages)
    else
        self.pages = resolve_pages(pages)
    end

    self.page_count = math.max(#self.pages - 1, 0)
    self.buttons = {}
    self.button_order = {}
    self.custom_buttons = opts.custom_buttons
    self.show_disabled = opts.show_disabled
    if self.show_disabled == nil then
        self.show_disabled = true
    end
    self.show_indicator = opts.show_indicator
    if self.show_indicator == nil then
        self.show_indicator = true
    end
    self.disable_on_timeout = opts.disable_on_timeout
    if self.disable_on_timeout == nil then
        self.disable_on_timeout = true
    end
    self.use_default_buttons = opts.use_default_buttons
    if self.use_default_buttons == nil then
        self.use_default_buttons = true
    end
    self.default_button_row = opts.default_button_row or 0
    self.loop_pages = opts.loop_pages or false
    self.custom_view = opts.custom_view
    self.author_check = opts.author_check
    if self.author_check == nil then
        self.author_check = true
    end
    self.user = nil
    self.menu = nil

    if self.custom_buttons and not self.use_default_buttons then
        for _, button in ipairs(self.custom_buttons) do
            self:add_button(button)
        end
    elseif not self.custom_buttons and self.use_default_buttons then
        self:add_default_buttons()
    end

    if self.show_menu then
        self:add_menu()
    end

    self:update_buttons()

    return self
end

function Paginator:add_default_buttons()
    local defaults = {
        PaginatorButton.new("first", { label = "<<", style = "primary", row = self.default_button_row }),
        PaginatorButton.new("prev", { label = "<", style = "danger", loop_label = "\xe2\x86\xaa", row = self.default_button_row }),
        PaginatorButton.new("page_indicator", { style = "secondary", disabled = true, row = self.default_button_row }),
        PaginatorButton.new("next", { label = ">", style = "success", loop_label = "\xe2\x86\xa9", row = self.default_button_row }),
        PaginatorButton.new("last", { label = ">>", style = "primary", row = self.default_button_row }),
    }
    for _, button in ipairs(defaults) do
        self:add_button(button)
    end
end

function Paginator:add_button(button)
    button.paginator = self
    if not self.buttons[button.button_type] then
        table.insert(self.button_order, button.button_type)
    end
    self.buttons[button.button_type] = {
        button = button,
        hidden = (button.button_type ~= "page_indicator") and button.disabled or (not self.show_indicator),
    }
    return self
end

function Paginator:remove_button(button_type)
    if not self.buttons[button_type] then
        error("no button_type " .. tostring(button_type) .. " was found in this paginator", 0)
    end
    self.buttons[button_type] = nil
    for i, existing in ipairs(self.button_order) do
        if existing == button_type then
            table.remove(self.button_order, i)
            break
        end
    end
    return self
end

function Paginator:add_menu()
    local options = {}
    for _, group in ipairs(self.page_groups or {}) do
        table.insert(options, {
            label = group.label,
            value = group.label,
            description = group.description,
        })
    end

    self.menu = Select.new({
        custom_id = "paginator_menu",
        placeholder = self.menu_placeholder,
        options = options,
        min_values = 1,
        max_values = 1,
    })
    self.menu.paginator = self
    self.menu.callback = function(interaction, values)
        self:_on_menu_select(interaction, values)
    end
    return self
end

function Paginator:_on_menu_select(_interaction, values)
    local selection = values and values[1]
    if not selection or not self.page_groups then
        return
    end
    for _, group in ipairs(self.page_groups) do
        if group.label == selection then
            self:apply_page_group(group)
            return
        end
    end
end

-- Applies a PageGroup's pages and per-group overrides to this paginator,
-- mirrors PaginatorMenu.callback calling Paginator.update in pycord.
function Paginator:apply_page_group(group)
    self.pages = resolve_pages(group.pages)
    self.page_count = math.max(#self.pages - 1, 0)
    self.current_page = 0

    if group.show_disabled ~= nil then
        self.show_disabled = group.show_disabled
    end
    if group.show_indicator ~= nil then
        self.show_indicator = group.show_indicator
    end
    if group.author_check ~= nil then
        self.author_check = group.author_check
    end
    if group.disable_on_timeout ~= nil then
        self.disable_on_timeout = group.disable_on_timeout
    end
    if group.loop_pages ~= nil then
        self.loop_pages = group.loop_pages
    end
    if group.custom_view ~= nil then
        self.custom_view = group.custom_view
    end
    if group.timeout ~= nil then
        self.timeout_ms = group.timeout
    end

    if group.use_default_buttons ~= nil then
        self.use_default_buttons = group.use_default_buttons
    end
    self.buttons = {}
    self.button_order = {}
    if self.use_default_buttons then
        self:add_default_buttons()
    elseif group.custom_buttons then
        for _, button in ipairs(group.custom_buttons) do
            self:add_button(button)
        end
    end

    self:update_buttons()
end

-- Recomputes each button's hidden/disabled state for the current page and
-- rebuilds self.items (the underlying View's component list) from scratch.
function Paginator:update_buttons()
    for _, button_type in ipairs(self.button_order) do
        local entry = self.buttons[button_type]
        local button = entry.button

        if button_type == "first" then
            entry.hidden = self.current_page <= 1
        elseif button_type == "last" then
            entry.hidden = self.current_page >= self.page_count - 1
        elseif button_type == "next" then
            if self.current_page == self.page_count then
                if not self.loop_pages then
                    entry.hidden = true
                    button.label = button.label
                else
                    button.label = button.loop_label
                end
            else
                entry.hidden = false
            end
        elseif button_type == "prev" then
            if self.current_page <= 0 then
                if not self.loop_pages then
                    entry.hidden = true
                else
                    button.label = button.loop_label
                end
            else
                entry.hidden = false
            end
        end
    end

    self:clear()

    if self.show_indicator and self.buttons.page_indicator then
        self.buttons.page_indicator.button.label = (self.current_page + 1) .. "/" .. (self.page_count + 1)
    end

    for _, button_type in ipairs(self.button_order) do
        local entry = self.buttons[button_type]
        local button = entry.button

        if button_type ~= "page_indicator" then
            if entry.hidden then
                button.disabled = true
                if self.show_disabled then
                    self:_add_nav_button(button)
                end
            else
                button.disabled = false
                self:_add_nav_button(button)
            end
        elseif self.show_indicator then
            self:_add_nav_button(button)
        end
    end

    if self.show_menu and self.menu then
        View.add(self, self.menu)
    end

    if self.custom_view then
        for _, item in ipairs(self.custom_view.items) do
            View.add(self, item)
        end
    end

    return self
end

function Paginator:_add_nav_button(paginator_button)
    local rendered = Button.new({
        style = paginator_button.style,
        label = paginator_button.label,
        emoji = paginator_button.emoji,
        disabled = paginator_button.disabled,
        custom_id = paginator_button.custom_id or ("paginator_" .. paginator_button.button_type),
        row = paginator_button.row,
    })
    rendered.callback = function(interaction)
        self:_on_nav_button(paginator_button.button_type, interaction)
    end
    View.add(self, rendered)
end

function Paginator:_on_nav_button(button_type, interaction)
    local new_page = self.current_page
    if button_type == "first" then
        new_page = 0
    elseif button_type == "prev" then
        if self.loop_pages and self.current_page == 0 then
            new_page = self.page_count
        else
            new_page = new_page - 1
        end
    elseif button_type == "next" then
        if self.loop_pages and self.current_page == self.page_count then
            new_page = 0
        else
            new_page = new_page + 1
        end
    elseif button_type == "last" then
        new_page = self.page_count
    end
    self:goto_page(new_page)
    if self.trigger_on_display then
        self:page_action(interaction)
    end
end

function Paginator:goto_page(page_number)
    page_number = page_number or 0
    self.current_page = page_number
    self:update_buttons()
    return self.pages[self.current_page + 1]
end

function Paginator:page_action(interaction)
    local page = self.pages[self.current_page + 1]
    if page and page.callback then
        page.callback(interaction)
    end
end

-- Builds the {content, embeds, components} payload for the current page,
-- ready to hand to ctx:respond / ctx:edit / rest:edit_message.
function Paginator:_render()
    local page = self.pages[self.current_page + 1]
    return {
        content = page.content,
        embeds = page.embeds,
        components = self:to_components(),
    }
end

function Paginator:respond(ctx, opts)
    opts = opts or {}
    self:update_buttons()
    self.user = ctx.author
    local render = self:_render()
    return ctx:respond(render.content, {
        embeds = render.embeds,
        components = render.components,
        ephemeral = opts.ephemeral,
    })
end

function Paginator:edit(ctx)
    self:update_buttons()
    local render = self:_render()
    return ctx:edit(render.content, {
        embeds = render.embeds,
        components = render.components,
    })
end

-- Disables every navigational button and returns the render payload for
-- the caller to send to the message/interaction. page, if given, replaces
-- the displayed content the same way pycord's disable(page=...) does.
function Paginator:disable(page)
    for _, button_type in ipairs(self.button_order) do
        self.buttons[button_type].button.disabled = true
    end
    self:clear()
    for _, button_type in ipairs(self.button_order) do
        local rendered_button = Button.new({
            style = self.buttons[button_type].button.style,
            label = self.buttons[button_type].button.label,
            custom_id = self.buttons[button_type].button.custom_id or ("paginator_" .. button_type),
            disabled = true,
            row = self.buttons[button_type].button.row,
        })
        View.add(self, rendered_button)
    end

    if page then
        local resolved = Page.from_value(page)
        return { content = resolved.content, embeds = resolved.embeds, components = self:to_components() }
    end
    return { components = self:to_components() }
end

-- Removes every button from the paginator's component list entirely and
-- returns the render payload for the caller to send.
function Paginator:cancel(page)
    self:clear()

    if page then
        local resolved = Page.from_value(page)
        return { content = resolved.content, embeds = resolved.embeds, components = {} }
    end
    return { components = {} }
end

return Paginator
