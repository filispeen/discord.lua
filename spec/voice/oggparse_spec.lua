require("spec_helper")

local OggStream = require("./voice/oggparse")

local function page(packets)
    local lacing, body = {}, {}
    for _, packet in ipairs(packets) do
        local remaining = #packet
        local offset = 1
        while remaining >= 255 do
            lacing[#lacing + 1] = string.char(255)
            body[#body + 1] = packet:sub(offset, offset + 254)
            offset = offset + 255
            remaining = remaining - 255
        end
        lacing[#lacing + 1] = string.char(remaining)
        body[#body + 1] = packet:sub(offset)
    end
    return "OggS" .. string.char(0, 0) .. string.rep("\0", 20) ..
        string.char(#lacing) .. table.concat(lacing) .. table.concat(body)
end

describe("OggStream", function()
    it("returns complete packets across fragmented input", function()
        local stream = OggStream.new()
        local data = page({ "OpusHead", "audio-frame" })

        stream:feed(data:sub(1, 11))
        assert.is_nil(stream:next_packet())

        stream:feed(data:sub(12))
        assert.equals("OpusHead", stream:next_packet())
        assert.equals("audio-frame", stream:next_packet())
        assert.is_nil(stream:next_packet())
    end)

    it("reassembles packets split by lacing values", function()
        local stream = OggStream.new()
        local packet = string.rep("x", 300)

        stream:feed(page({ packet }))

        assert.equals(packet, stream:next_packet())
    end)

    it("rejects invalid page magic", function()
        local stream = OggStream.new()

        assert.has_error(function()
            stream:feed("BAD!" .. string.rep("\0", 23))
        end)
    end)
end)
