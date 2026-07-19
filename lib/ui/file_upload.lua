-- lib/ui/file_upload.lua
-- File component (Components V2), contract mirrors pycord discord.ui.File.
-- Displays an uploaded attachment inline in a message, distinct from the
-- Modal input_text file upload field.
--
-- Public Contract:
--   FileUpload.new(opts) -> file_upload
--     opts.url: string - must be an attachment:// reference
--     opts.spoiler: boolean or nil - defaults to false
--
--   file_upload:to_component() -> table
--     Serializes to the Discord File component payload (type 13).

local class = require("core.class")
local Item = require("ui.item")

local FileUpload = class("FileUpload", Item)

function FileUpload.new(opts)
    opts = opts or {}
    local self = setmetatable(Item.new("file_upload"), FileUpload)

    if opts.url == nil then
        error("url is required for FileUpload")
    end
    if not tostring(opts.url):match("^attachment://") then
        error("FileUpload url must be an attachment:// reference")
    end

    self.url = opts.url
    self.spoiler = opts.spoiler or false

    return self
end

function FileUpload:to_component()
    return {
        type = 13,
        file = { url = self.url },
        spoiler = self.spoiler,
    }
end

return FileUpload
