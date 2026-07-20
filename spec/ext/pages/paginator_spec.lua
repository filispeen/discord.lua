-- spec/ext/pages/paginator_spec.lua
-- Tests for Paginator

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local Paginator = require("ext.pages.paginator")
local Page = require("ext.pages.page")
local PageGroup = require("ext.pages.page_group")
local PaginatorButton = require("ext.pages.paginator_button")

local function make_ctx()
    local calls = { respond = {}, edit = {} }
    return {
        author = { id = "user1" },
        respond = function(_self, content, opts)
            table.insert(calls.respond, { content = content, opts = opts })
            return { ok = true }
        end,
        edit = function(_self, content, opts)
            table.insert(calls.edit, { content = content, opts = opts })
            return { ok = true }
        end,
    }, calls
end

describe("Paginator", function()
    describe("Paginator.new", function()
        it("requires pages", function()
            assert.has_error(function()
                Paginator.new({})
            end)
        end)

        it("resolves string pages into Page instances", function()
            local paginator = Paginator.new({ pages = { "one", "two", "three" } })
            assert.equals(3, #paginator.pages)
            assert.equals("one", paginator.pages[1].content)
        end)

        it("accepts already-built Page instances", function()
            local page = Page.new({ content = "hi" })
            local paginator = Paginator.new({ pages = { page } })
            assert.equals(page, paginator.pages[1])
        end)

        it("sets page_count to the zero-indexed last page", function()
            local paginator = Paginator.new({ pages = { "a", "b", "c" } })
            assert.equals(2, paginator.page_count)
        end)

        it("starts on page 0", function()
            local paginator = Paginator.new({ pages = { "a", "b" } })
            assert.equals(0, paginator.current_page)
        end)

        it("adds default navigation buttons when use_default_buttons is true", function()
            local paginator = Paginator.new({ pages = { "a", "b", "c" } })
            assert.is_not_nil(paginator.buttons.first)
            assert.is_not_nil(paginator.buttons.prev)
            assert.is_not_nil(paginator.buttons.next)
            assert.is_not_nil(paginator.buttons.last)
            assert.is_not_nil(paginator.buttons.page_indicator)
        end)

        it("uses custom_buttons instead when use_default_buttons is false", function()
            local custom = { PaginatorButton.new("next", { label = "Forward" }) }
            local paginator = Paginator.new({ pages = { "a", "b" }, use_default_buttons = false, custom_buttons = custom })
            assert.is_nil(paginator.buttons.first)
            assert.is_not_nil(paginator.buttons.next)
        end)

        it("resolves a list of PageGroups by picking the default group", function()
            local group_a = PageGroup.new({ label = "A", pages = { "a1", "a2" } })
            local group_b = PageGroup.new({ label = "B", pages = { "b1" }, default = true })
            local paginator = Paginator.new({ pages = { group_a, group_b } })

            assert.equals(1, #paginator.pages)
            assert.equals("b1", paginator.pages[1].content)
        end)

        it("errors when more than one PageGroup is marked default", function()
            local group_a = PageGroup.new({ label = "A", pages = { "a1" }, default = true })
            local group_b = PageGroup.new({ label = "B", pages = { "b1" }, default = true })
            assert.has_error(function()
                Paginator.new({ pages = { group_a, group_b } })
            end)
        end)
    end)

    describe("Paginator:goto_page", function()
        it("updates current_page and returns the resolved Page", function()
            local paginator = Paginator.new({ pages = { "a", "b", "c" } })
            local page = paginator:goto_page(2)
            assert.equals(2, paginator.current_page)
            assert.equals("c", page.content)
        end)

        it("defaults to page 0 when called with no argument", function()
            local paginator = Paginator.new({ pages = { "a", "b" } })
            paginator:goto_page(1)
            paginator:goto_page()
            assert.equals(0, paginator.current_page)
        end)
    end)

    describe("Paginator:update_buttons", function()
        it("hides first/prev on the first page when not looping", function()
            local paginator = Paginator.new({ pages = { "a", "b", "c" } })
            assert.is_true(paginator.buttons.first.hidden)
            assert.is_true(paginator.buttons.prev.hidden)
        end)

        it("hides last/next on the final page when not looping", function()
            local paginator = Paginator.new({ pages = { "a", "b", "c" } })
            paginator:goto_page(2)
            assert.is_true(paginator.buttons.last.hidden)
            assert.is_true(paginator.buttons.next.hidden)
        end)

        it("does not hide next on the final page when looping", function()
            local paginator = Paginator.new({ pages = { "a", "b", "c" }, loop_pages = true })
            paginator:goto_page(2)
            assert.is_false(paginator.buttons.next.hidden)
        end)

        it("sets the page indicator label to current/total", function()
            local paginator = Paginator.new({ pages = { "a", "b", "c" } })
            paginator:goto_page(1)
            assert.equals("2/3", paginator.buttons.page_indicator.button.label)
        end)

        it("populates items with rendered buttons after construction", function()
            local paginator = Paginator.new({ pages = { "a", "b", "c" } })
            assert.is_true(#paginator.items > 0)
        end)
    end)

    describe("Paginator:respond and Paginator:edit", function()
        it("respond sends the current page's content and components", function()
            local paginator = Paginator.new({ pages = { "hello", "world" } })
            local ctx, calls = make_ctx()

            paginator:respond(ctx)

            assert.equals(1, #calls.respond)
            assert.equals("hello", calls.respond[1].content)
            assert.is_not_nil(calls.respond[1].opts.components)
        end)

        it("respond passes ephemeral through to ctx:respond", function()
            local paginator = Paginator.new({ pages = { "hello" } })
            local ctx, calls = make_ctx()

            paginator:respond(ctx, { ephemeral = true })

            assert.is_true(calls.respond[1].opts.ephemeral)
        end)

        it("edit sends the current page after navigating", function()
            local paginator = Paginator.new({ pages = { "hello", "world" } })
            local ctx, calls = make_ctx()

            paginator:goto_page(1)
            paginator:edit(ctx)

            assert.equals(1, #calls.edit)
            assert.equals("world", calls.edit[1].content)
        end)
    end)

    describe("Paginator:disable", function()
        it("disables every navigational button", function()
            local paginator = Paginator.new({ pages = { "a", "b", "c" } })
            paginator:goto_page(1)
            paginator:disable()

            for _, button_type in ipairs(paginator.button_order) do
                assert.is_true(paginator.buttons[button_type].button.disabled)
            end
        end)

        it("returns a render payload with the disabled components", function()
            local paginator = Paginator.new({ pages = { "a", "b", "c" } })
            local render = paginator:disable()
            assert.is_not_nil(render.components)
        end)

        it("replaces content when a page is given", function()
            local paginator = Paginator.new({ pages = { "a", "b" } })
            local render = paginator:disable("done")
            assert.equals("done", render.content)
        end)
    end)

    describe("Paginator:cancel", function()
        it("clears every component", function()
            local paginator = Paginator.new({ pages = { "a", "b" } })
            local render = paginator:cancel()
            assert.same({}, render.components)
        end)

        it("replaces content when a page is given", function()
            local paginator = Paginator.new({ pages = { "a", "b" } })
            local render = paginator:cancel("cancelled")
            assert.equals("cancelled", render.content)
        end)
    end)

    describe("Paginator:page_action", function()
        it("invokes the current page's callback", function()
            local invoked = false
            local page = Page.new({ content = "hi", callback = function() invoked = true end })
            local paginator = Paginator.new({ pages = { page } })

            paginator:page_action()

            assert.is_true(invoked)
        end)

        it("does nothing when the current page has no callback", function()
            local paginator = Paginator.new({ pages = { "hi" } })
            assert.has_no.errors(function()
                paginator:page_action()
            end)
        end)
    end)

    describe("Paginator:add_button and Paginator:remove_button", function()
        it("add_button attaches a new PaginatorButton", function()
            local paginator = Paginator.new({ pages = { "a" }, use_default_buttons = false })
            paginator:add_button(PaginatorButton.new("first"))
            assert.is_not_nil(paginator.buttons.first)
        end)

        it("remove_button detaches a button by type", function()
            local paginator = Paginator.new({ pages = { "a", "b", "c" } })
            paginator:remove_button("first")
            assert.is_nil(paginator.buttons.first)
        end)

        it("remove_button errors for an unknown button_type", function()
            local paginator = Paginator.new({ pages = { "a" } })
            assert.has_error(function()
                paginator:remove_button("teleport")
            end)
        end)
    end)

    describe("Paginator with PageGroups and show_menu", function()
        it("adds a select menu item when show_menu is true", function()
            local group_a = PageGroup.new({ label = "A", pages = { "a1" }, default = true })
            local group_b = PageGroup.new({ label = "B", pages = { "b1" } })
            local paginator = Paginator.new({ pages = { group_a, group_b }, show_menu = true })

            assert.is_not_nil(paginator.menu)
        end)

        it("apply_page_group swaps pages and resets to page 0", function()
            local group_a = PageGroup.new({ label = "A", pages = { "a1", "a2" }, default = true })
            local group_b = PageGroup.new({ label = "B", pages = { "b1" } })
            local paginator = Paginator.new({ pages = { group_a, group_b }, show_menu = true })

            paginator:goto_page(1)
            paginator:apply_page_group(group_b)

            assert.equals(0, paginator.current_page)
            assert.equals(1, #paginator.pages)
            assert.equals("b1", paginator.pages[1].content)
        end)
    end)
end)
