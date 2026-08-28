local class = require("../core/class")

local File = class("File")

local function basename(path)
    return path:match("([^/\\]+)$") or path
end

local function filename(name, spoiler)
    if spoiler and name:sub(1, 8) ~= "SPOILER_" then
        return "SPOILER_" .. name
    end
    return name
end

function File.from_bytes(data, name, opts)
    opts = opts or {}
    if type(data) ~= "string" then
        error("File.from_bytes data must be a string", 0)
    end
    if not name or name == "" then
        error("File.from_bytes requires a filename", 0)
    end
    local self = setmetatable({}, File)
    self.data = data
    self.filename = filename(name, opts.spoiler)
    self.description = opts.description
    self.content_type = opts.content_type or "application/octet-stream"
    return self
end

function File.new(path, opts)
    opts = opts or {}
    if not path or path == "" then
        error("File.new requires a path", 0)
    end
    local handle, err = io.open(path, "rb")
    if not handle then
        error("File.new could not open " .. tostring(path) .. ": " .. tostring(err), 0)
    end
    local data = handle:read("*a")
    handle:close()
    return File.from_bytes(data, opts.filename or basename(path), opts)
end

function File:attachment(index)
    local result = {
        id = tostring(index),
        filename = self.filename,
    }
    if self.description ~= nil then
        result.description = self.description
    end
    return result
end

return File
