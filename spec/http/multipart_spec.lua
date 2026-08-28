require("spec_helper")

local File = require("./models/file")
local Multipart = require("./http/multipart")

describe("File", function()
    it("builds upload metadata from bytes", function()
        local file = File.from_bytes("hello", "note.txt", { description = "note", spoiler = true, content_type = "text/plain" })

        assert.equals("SPOILER_note.txt", file.filename)
        assert.equals("text/plain", file.content_type)
        assert.same({ id = "0", filename = "SPOILER_note.txt", description = "note" }, file:attachment(0))
    end)
end)

describe("multipart", function()
    it("adds file attachments to a message payload", function()
        local file = File.from_bytes("hello", "note.txt")
        local payload = Multipart.with_attachments({ content = "hello" }, { file })

        assert.equals("hello", payload.content)
        assert.same({ id = "0", filename = "note.txt" }, payload.attachments[1])
    end)

    it("builds a payload_json part and file part", function()
        local file = File.from_bytes("hello", "note.txt", { content_type = "text/plain" })
        local body, content_type = Multipart.build({ content = "hello" }, { file })

        assert.is_truthy(body:find("name=\"payload_json\"", 1, true))
        assert.is_truthy(body:find("name=\"files[0]\"; filename=\"note.txt\"", 1, true))
        assert.is_truthy(body:find("hello", 1, true))
        assert.is_truthy(content_type:find("multipart/form-data; boundary=", 1, true))
    end)
end)
