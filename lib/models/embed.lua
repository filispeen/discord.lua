-- lib/models/embed.lua
-- Embed model for Discord API
--
-- Public Contract:
--   Embed.new(data) -> Embed
--     Creates a new Embed from API data.
--
--   Embed:title -> string or nil
--     Embed title.
--
--   Embed:description -> string or nil
--     Embed description.
--
--   Embed:url -> string or nil
--     Embed URL (with thumbnail).
--
--   Embed:image -> string or nil
--     Embed image URL.
--
--   Embed:thumbnail -> string or nil
--     Embed thumbnail URL.
--
--   Embed:author -> table or nil
--     Embed author.
--
--   Embed:footer -> table or nil
--     Embed footer.
--
--   Embed:color -> number
--     Embed color (hex).
--
--   Embed:fields -> table
--     Embed fields.
--
--   Embed:timestamp -> string or nil
--     Embed timestamp.
--
--   Embed:new(title, description, color) -> Embed
--     Creates a new Embed with optional fields.
--
--   Embed:with_author(name, url, icon_url) -> Embed
--     Adds author to embed.
--
--   Embed:with_thumbnail(url) -> Embed
--     Adds thumbnail to embed.
--
--   Embed:with_image(url) -> Embed
--     Adds image to embed.
--
--   Embed:with_footer(text, icon_url) -> Embed
--     Adds footer to embed.
--
--   Embed:with_timestamp() -> Embed
--     Adds current timestamp to embed.
--
--   Embed:with_field(name, value, inline) -> Embed
--     Adds a field to embed.

local class = require("core.class")

-- Embed class
local Embed = class("Embed")

function Embed.new(data)
    local self = {}
    setmetatable(self, {
        __index = Embed
    })

    self.title = data.title
    self.type = data.type or "rich"
    self.url = data.url
    self.description = data.description
    self.color = data.color or 0
    self.timestamp = data.timestamp
    self.footer = data.footer
    self.image = data.image
    self.thumbnail = data.thumbnail
    self.author = data.author
    self.fields = data.fields or {}

    return self
end

-- Create a new embed
function Embed.create(title, description, color)
    local embed = Embed.new({
        title = title,
        description = description,
        color = color or 0x000000,
    })
    return embed
end

-- Add author to embed
function Embed:with_author(name, url, icon_url)
    self.author = {
        name = name,
        url = url,
        icon_url = icon_url,
    }
    return self
end

-- Add thumbnail to embed
function Embed:with_thumbnail(url)
    self.thumbnail = url
    return self
end

-- Add image to embed
function Embed:with_image(url)
    self.image = url
    return self
end

-- Add footer to embed
function Embed:with_footer(text, icon_url)
    self.footer = {
        text = text,
        icon_url = icon_url,
    }
    return self
end

-- Add timestamp to embed
function Embed:with_timestamp()
    self.timestamp = os.date("%Y-%m-%dT%H:%M:%SZ")
    return self
end

-- Add a field to embed
function Embed:with_field(name, value, inline)
    table.insert(self.fields, {
        name = name,
        value = value,
        inline = inline or false,
    })
    return self
end

-- Set color
function Embed:color(color)
    self.color = color
    return self
end

-- Set title
function Embed:title(title)
    self.title = title
    return self
end

-- Set description
function Embed:description(desc)
    self.description = desc
    return self
end

return Embed
