-- spec/ext/pages/page_spec.lua
-- Tests for Page

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local Page = require("ext.pages.page")

describe("Page", function()
    describe("Page.new", function()
        it("stores content, embeds, custom_view, callback", function()
            local callback = function() end
            local view = { items = {} }
            local page = Page.new({ content = "hi", embeds = { { title = "e" } }, custom_view = view, callback = callback })

            assert.equals("hi", page.content)
            assert.equals(1, #page.embeds)
            assert.equals(view, page.custom_view)
            assert.equals(callback, page.callback)
        end)

        it("defaults embeds to an empty table", function()
            local page = Page.new({ content = "hi" })
            assert.same({}, page.embeds)
        end)

        it("errors when content, embeds, and custom_view are all nil", function()
            assert.has_error(function()
                Page.new({})
            end)
        end)

        it("accepts embeds alone", function()
            local page = Page.new({ embeds = { { title = "e" } } })
            assert.is_nil(page.content)
        end)

        it("accepts custom_view alone", function()
            local view = { items = {} }
            local page = Page.new({ custom_view = view })
            assert.equals(view, page.custom_view)
        end)
    end)

    describe("Page.from_value", function()
        it("passes through an existing Page unchanged", function()
            local page = Page.new({ content = "hi" })
            assert.equals(page, Page.from_value(page))
        end)

        it("wraps a string as content", function()
            local page = Page.from_value("hello")
            assert.equals("hello", page.content)
        end)

        it("wraps a single embed-shaped table into embeds", function()
            local embed = { title = "My embed" }
            local page = Page.from_value(embed)
            assert.equals(1, #page.embeds)
            assert.equals(embed, page.embeds[1])
        end)

        it("wraps a list of embeds directly", function()
            local embeds = { { title = "one" }, { title = "two" } }
            local page = Page.from_value(embeds)
            assert.equals(2, #page.embeds)
        end)

        it("wraps a View-shaped table (has items, no embed fields) as custom_view", function()
            local view = { items = {} }
            local page = Page.from_value(view)
            assert.equals(view, page.custom_view)
        end)

        it("errors on an unrecognized type", function()
            assert.has_error(function()
                Page.from_value(42)
            end)
        end)
    end)
end)
