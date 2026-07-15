-- spec/models/embed_spec.lua
-- Tests for embed model

-- Setup package path to find lib modules
package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

-- Mock luv before loading gateway modules
package.loaded["luv"] = {
    timer = {
        new = function()
            return {
                start = function() end,
                stop = function() end,
            }
        end
    },
    now = function() return 0 end
}

local M = require("models.embed")
local Embed = M

describe("Embed", function()
    it("creates a new embed", function()
        local embed = Embed.new({
            title = "Test Title",
            description = "Test Description",
            url = "https://example.com",
            color = 0xFF0000,
            timestamp = "2024-01-01T00:00:00Z",
            footer = {
                text = "Footer Text",
                icon_url = "icon.png",
            },
            image = "https://example.com/image.png",
            thumbnail = "https://example.com/thumbnail.png",
            author = {
                name = "Author",
                url = "https://example.com/author",
                icon_url = "author.png",
            },
            fields = {
                {
                    name = "Field 1",
                    value = "Value 1",
                    inline = true,
                },
            },
            provider = {
                name = "Provider",
                url = "https://example.com/provider",
                image_url = "provider.png",
            },
            video = {
                url = "https://example.com/video.mp4",
            },
        })

        assert.equals("Test Title", embed.title)
        assert.equals("Test Description", embed.description)
        assert.equals("https://example.com", embed.url)
        assert.equals(0xFF0000, embed.color)
        assert.equals("2024-01-01T00:00:00Z", embed.timestamp)
        assert.equals("Footer Text", embed.footer.text)
        assert.equals("https://example.com/image.png", embed.image)
        assert.equals("https://example.com/thumbnail.png", embed.thumbnail)
        assert.equals("Author", embed.author.name)
        assert.equals(1, #embed.fields)
        assert.equals("Provider", embed.provider.name)
        assert.equals("https://example.com/video.mp4", embed.video.url)
    end)

    it("create creates empty embed", function()
        local embed = Embed.new({})
        assert.equals(nil, rawget(embed, "title"))
        assert.equals(nil, rawget(embed, "description"))
        assert.equals(0, embed.color)
    end)

    it("with_author adds author", function()
        local embed = Embed.new({})
        embed:with_author("Author Name", "https://example.com", "icon.png")

        assert.equals("Author Name", embed.author.name)
        assert.equals("https://example.com", embed.author.url)
        assert.equals("icon.png", embed.author.icon_url)
    end)

    it("with_thumbnail adds thumbnail", function()
        local embed = Embed.new({})
        embed:with_thumbnail("https://example.com/thumb.png")

        assert.equals("https://example.com/thumb.png", embed.thumbnail)
    end)

    it("with_image adds image", function()
        local embed = Embed.new({})
        embed:with_image("https://example.com/image.png")

        assert.equals("https://example.com/image.png", embed.image)
    end)

    it("with_video adds video", function()
        local embed = Embed.new({})
        embed:with_video("https://example.com/video.mp4")

        assert.is_not_nil(embed.video)
        assert.equals("https://example.com/video.mp4", embed.video.url)
    end)

    it("with_provider adds provider", function()
        local embed = Embed.new({})
        embed:with_provider("Provider Name", "https://example.com", "provider.png")

        assert.equals("Provider Name", embed.provider.name)
        assert.equals("https://example.com", embed.provider.url)
        assert.equals("provider.png", embed.provider.image_url)
    end)

    it("with_footer adds footer", function()
        local embed = Embed.new({})
        embed:with_footer("Footer Text", "icon.png")

        assert.equals("Footer Text", embed.footer.text)
        assert.equals("icon.png", embed.footer.icon_url)
    end)

    it("with_timestamp adds timestamp", function()
        local embed = Embed.new({})
        embed:with_timestamp()

        assert.is_not_nil(embed.timestamp)
        -- Just verify timestamp is set, don't check exact value
        assert.equals("Z", embed.timestamp:sub(-1))
    end)

    it("with_field adds field", function()
        local embed = Embed.new({})
        embed:with_field("Field Name", "Field Value", true)

        assert.equals(1, #embed.fields)
        assert.equals("Field Name", embed.fields[1].name)
        assert.equals("Field Value", embed.fields[1].value)
        assert.is_true(embed.fields[1].inline)
    end)

    it("with_fields adds multiple fields", function()
        local embed = Embed.new({})
        embed:with_fields({
            { name = "Field 1", value = "Value 1" },
            { name = "Field 2", value = "Value 2", inline = true },
        })

        assert.equals(2, #embed.fields)
        assert.equals("Field 1", embed.fields[1].name)
        assert.equals("Value 1", embed.fields[1].value)
        assert.is_false(embed.fields[1].inline)
        assert.equals("Field 2", embed.fields[2].name)
        assert.is_true(embed.fields[2].inline)
    end)

    it("with_color sets color", function()
        local embed = Embed.new({})
        embed:with_color(0xFF0000)

        assert.equals(0xFF0000, embed.color)
    end)

    it("title sets title and url", function()
        local embed = Embed.new({})
        embed:title("Test Title", "https://example.com", 0xFF0000)

        assert.equals("Test Title", embed.title)
        assert.equals("https://example.com", embed.url)
        assert.equals(0xFF0000, embed.color)
    end)

    it("description sets description", function()
        local embed = Embed.new({})
        embed:description("Test Description", 0xFF0000)

        assert.equals("Test Description", embed.description)
        assert.equals(0xFF0000, embed.color)
    end)
end)
