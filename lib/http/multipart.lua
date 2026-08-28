local json = require("../core/json_compat")

local Multipart = {}

local counter = 0

local function boundary()
    counter = counter + 1
    return "discordlua" .. tostring(os.time()) .. tostring(counter)
end

function Multipart.attachments(files)
    local attachments = {}
    for index, file in ipairs(files or {}) do
        attachments[index] = file:attachment(index - 1)
    end
    return attachments
end

function Multipart.with_attachments(payload, files)
    local result = {}
    for key, value in pairs(payload or {}) do
        result[key] = value
    end
    if files and #files > 0 and result.attachments == nil then
        result.attachments = Multipart.attachments(files)
    end
    return result
end

function Multipart.build(payload, files)
    local token = boundary()
    local parts = {}
    local function add(headers, value)
        parts[#parts + 1] = "--" .. token .. "\r\n"
        for key, header_value in pairs(headers) do
            parts[#parts + 1] = key .. ": " .. header_value .. "\r\n"
        end
        parts[#parts + 1] = "\r\n"
        parts[#parts + 1] = value
        parts[#parts + 1] = "\r\n"
    end

    add({ ["Content-Disposition"] = "form-data; name=\"payload_json\"", ["Content-Type"] = "application/json" }, json.encode(payload or {}))
    for index, file in ipairs(files or {}) do
        add({
            ["Content-Disposition"] = "form-data; name=\"files[" .. (index - 1) .. "]\"; filename=\"" .. file.filename .. "\"",
            ["Content-Type"] = file.content_type,
        }, file.data)
    end
    parts[#parts + 1] = "--" .. token .. "--\r\n"
    return table.concat(parts), "multipart/form-data; boundary=" .. token
end

return Multipart
