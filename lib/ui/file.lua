local class = require("../core/class")
local Item = require("./item")

local File = class("File", Item)

function File.new(opts)
    opts = opts or {}
    local self = setmetatable(Item.new("file"), File)
    if opts.url == nil or not tostring(opts.url):match("^attachment://") then error("File url must be an attachment:// reference", 0) end
    self.url = opts.url
    self.spoiler = opts.spoiler or false
    self.id = opts.id
    return self
end

function File:to_component()
    local result = { type = 13, file = { url = self.url }, spoiler = self.spoiler }
    if self.id ~= nil then result.id = self.id end
    return result
end

return File
