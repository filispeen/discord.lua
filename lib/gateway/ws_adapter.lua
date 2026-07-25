-- lib/gateway/ws_adapter.lua
-- Adapts coro-websocket's low-level (res, read, write) coroutine API into
-- an EventEmitter-style object with :on, :send, :close methods, since the
-- rest of the codebase (Shard, voice_gateway) was written against an
-- EventEmitter-style websocket contract that coro-websocket does not
-- provide directly.
--
-- Public Contract:
--   wrap(res, read, write) -> ws
--     res: table - handshake response from coro-websocket.connect
--     read: function - blocking coroutine read, returns {opcode, payload} or nil
--     write: function - blocking coroutine write, accepts {opcode, payload}
--     Returns: ws object with :on(event, fn), :send(text), :close(code, reason)
--     Events emitted: "open", "message", "close", "error"
--     The read loop must be pumped by calling ws:start_reading() once
--     listeners are attached; this runs the receive loop in a coroutine.

local Emitter = require("core.emitter")

local TEXT_OPCODE = 1

local M = {}

function M.wrap(_res, read, write)
    local ws = Emitter()
    ws._read = read
    ws._write = write
    ws._closed = false

    function ws:send(text)
        if self._closed then
            return
        end
        coroutine.wrap(function()
            local ok, err = pcall(self._write, { opcode = TEXT_OPCODE, payload = text })
            if not ok then
                self:emit("error", err)
            end
        end)()
    end

    function ws:close()
        if self._closed then
            return
        end
        self._closed = true
        coroutine.wrap(function()
            pcall(self._write)
        end)()
    end

    function ws:start_reading()
        coroutine.wrap(function()
            self:emit("open")
            while true do
                local ok, message = pcall(self._read)
                if not ok then
                    self._closed = true
                    self:emit("error", message)
                    self:emit("close", 1006, tostring(message))
                    return
                end
                if not message then
                    self._closed = true
                    self:emit("close", 1000, "Connection closed")
                    return
                end
                self:emit("message", message.payload)
            end
        end)()
    end

    return ws
end

return M
