-- spec/ui/thumbnail_spec.lua
-- Tests for the Thumbnail UI component (Components V2)

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local Thumbnail = require("ui.thumbnail")

describe("Thumbnail", function()
    it("creates a thumbnail with a url", function()
        local thumbnail = Thumbnail.new({ url = "attachment://image.png" })
        assert.equals("attachment://image.png", thumbnail.url)
        assert.is_false(thumbnail.spoiler)
    end)

    it("requires a url", function()
        assert.has_error(function()
            Thumbnail.new({})
        end)
    end)

    it("rejects a description over 1024 characters", function()
        local long_description = string.rep("a", 1025)
        assert.has_error(function()
            Thumbnail.new({ url = "attachment://image.png", description = long_description })
        end)
    end)

    it("serializes to a type 11 component", function()
        local thumbnail = Thumbnail.new({
            url = "attachment://image.png",
            description = "An image",
            spoiler = true,
        })
        local component = thumbnail:to_component()

        assert.equals(11, component.type)
        assert.equals("attachment://image.png", component.media.url)
        assert.equals("An image", component.description)
        assert.is_true(component.spoiler)
    end)
end)
