-- spec/ui/file_upload_spec.lua
-- Tests for the File (FileUpload) UI component (Components V2)

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local FileUpload = require("ui.file_upload")

describe("FileUpload", function()
    it("creates a file component with an attachment url", function()
        local file = FileUpload.new({ url = "attachment://report.pdf" })
        assert.equals("attachment://report.pdf", file.url)
        assert.is_false(file.spoiler)
    end)

    it("requires a url", function()
        assert.has_error(function()
            FileUpload.new({})
        end)
    end)

    it("rejects a non attachment:// url", function()
        assert.has_error(function()
            FileUpload.new({ url = "https://example.com/report.pdf" })
        end)
    end)

    it("serializes to a type 13 component", function()
        local file = FileUpload.new({ url = "attachment://report.pdf", spoiler = true })
        local component = file:to_component()

        assert.equals(13, component.type)
        assert.equals("attachment://report.pdf", component.file.url)
        assert.is_true(component.spoiler)
    end)
end)
