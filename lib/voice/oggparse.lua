local OggStream = {}
OggStream.__index = OggStream

function OggStream.new()
    return setmetatable({
        _buffer = "",
        _packets = {},
        _partial = {},
    }, OggStream)
end

function OggStream:feed(data)
    if type(data) ~= "string" then
        error("OggStream:feed expects a string", 0)
    end

    self._buffer = self._buffer .. data

    while true do
        if #self._buffer < 27 then
            return
        end
        if self._buffer:sub(1, 4) ~= "OggS" then
            error("OggStream invalid header magic", 0)
        end
        if self._buffer:byte(5) ~= 0 then
            error("OggStream unsupported version", 0)
        end

        local segments = self._buffer:byte(27)
        local header_size = 27 + segments
        if #self._buffer < header_size then
            return
        end

        local body_size = 0
        for i = 1, segments do
            body_size = body_size + self._buffer:byte(27 + i)
        end
        local page_size = header_size + body_size
        if #self._buffer < page_size then
            return
        end

        local offset = header_size + 1
        for i = 1, segments do
            local size = self._buffer:byte(27 + i)
            self._partial[#self._partial + 1] = self._buffer:sub(offset, offset + size - 1)
            offset = offset + size
            if size < 255 then
                self._packets[#self._packets + 1] = table.concat(self._partial)
                self._partial = {}
            end
        end
        self._buffer = self._buffer:sub(page_size + 1)
    end
end

function OggStream:next_packet()
    if #self._packets == 0 then
        return nil
    end
    return table.remove(self._packets, 1)
end

function OggStream:has_packets()
    return #self._packets > 0
end

return OggStream
