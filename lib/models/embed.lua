-- lib/models/embed.lua
-- Embed model for Discord API

local class = require("core.class")

-- Embed class
local Embed = class("Embed")

function Embed.new(data)
    data = data or {}
    local self = {}
    setmetatable(self, { __index = Embed })

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
    self.provider = data.provider
    self.video = data.video
    self.attachments = data.attachments or {}
    self.mentions = data.mentions or {}
    self.mention_roles = data.mention_roles or {}
    self.mention_channels = data.mention_channels or {}
    self.pinned = data.pinned or false
    self.webhook_id = data.webhook_id

    self.to_json = Embed.to_json

    return self
end

function Embed.with_author(self, name, url, icon_url, color)
    self.author = {name = name, url = url, icon_url = icon_url}
    if color then self:with_color(color) end
    return self
end

function Embed.with_thumbnail(self, url, color)
    self.thumbnail = url
    if color then self:with_color(color) end
    return self
end

function Embed.with_image(self, url, color)
    self.image = url
    if color then self:with_color(color) end
    return self
end

function Embed.with_video(self, url, color)
    self.video = {url = url}
    if color then self:with_color(color) end
    return self
end

function Embed.with_provider(self, name, url, image_url, color)
    self.provider = {name = name, url = url, image_url = image_url}
    if color then self:with_color(color) end
    return self
end

function Embed.with_footer(self, text, icon_url, color)
    self.footer = {text = text, icon_url = icon_url}
    if color then self:with_color(color) end
    return self
end

function Embed.with_timestamp(self)
    self.timestamp = os.date("%Y-%m-%dT%H:%M:%SZ")
    return self
end

function Embed.with_field(self, name, value, inline)
    table.insert(self.fields, {name = name, value = value, inline = inline or false})
    return self
end

function Embed.with_fields(self, fields)
    for _, field in ipairs(fields) do
        self:with_field(field.name, field.value, field.inline)
    end
    return self
end

function Embed.with_color(self, color)
    self.color = color
    return self
end

function Embed.title(self, title, url, color)
    self.title = title
    self.url = url
    if color then self:with_color(color) end
    return self
end

function Embed.description(self, desc, color)
    self.description = desc
    if color then self:with_color(color) end
    return self
end

function Embed.to_json(self)
    local json = require("json") or require("dkjson")
    return json.encode(self)
end

-- Create a new embed (factory function)
function Embed.create()
    return Embed.new({})
end

return Embed
