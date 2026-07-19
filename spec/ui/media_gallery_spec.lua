-- spec/ui/media_gallery_spec.lua
-- Tests for the MediaGallery UI component (Components V2)

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local MediaGallery = require("ui.media_gallery")

describe("MediaGallery", function()
    it("creates a gallery with items", function()
        local gallery = MediaGallery.new({
            { url = "attachment://a.png" },
            { url = "attachment://b.png" },
        })
        assert.equals(2, #gallery.items)
    end)

    it("defaults to an empty item list", function()
        local gallery = MediaGallery.new()
        assert.equals(0, #gallery.items)
    end)

    it("rejects more than 10 items at construction", function()
        local items = {}
        for i = 1, 11 do
            items[i] = { url = "attachment://" .. i .. ".png" }
        end
        assert.has_error(function()
            MediaGallery.new(items)
        end)
    end)

    it("requires each item to have a url", function()
        assert.has_error(function()
            MediaGallery.new({ { description = "no url" } })
        end)
    end)

    it("add_item appends an item", function()
        local gallery = MediaGallery.new()
        gallery:add_item({ url = "attachment://a.png" })
        assert.equals(1, #gallery.items)
    end)

    it("add_item rejects a 11th item", function()
        local gallery = MediaGallery.new()
        for i = 1, 10 do
            gallery:add_item({ url = "attachment://" .. i .. ".png" })
        end
        assert.has_error(function()
            gallery:add_item({ url = "attachment://11.png" })
        end)
    end)

    it("serializes to a type 12 component", function()
        local gallery = MediaGallery.new({
            { url = "attachment://a.png", description = "A", spoiler = true },
        })
        local component = gallery:to_component()

        assert.equals(12, component.type)
        assert.equals(1, #component.items)
        assert.equals("attachment://a.png", component.items[1].media.url)
        assert.equals("A", component.items[1].description)
        assert.is_true(component.items[1].spoiler)
    end)
end)
