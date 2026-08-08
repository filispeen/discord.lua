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
--     Returns: ws object with :on(event, fn), :send(text), :send_bytes(bytes),
--     :close(code, reason)
--     Events emitted: "open", "message", "close", "error"
--       "message" passes (self, payload, is_binary): is_binary is true for
--       WebSocket binary frames (opcode 2, used by the voice gateway's
--       DAVE/MLS opcodes, see voice/dave_session.lua) and false for text
--       frames (opcode 1, everything else). Callers that only care about
--       JSON text frames (gateway.Shard) can keep ignoring the third
--       argument exactly as before.
--     The read loop must be pumped by calling ws:start_reading() once
--     listeners are attached; this runs the receive loop in a coroutine.

local Emitter = require("../core/emitter")

local TEXT_OPCODE = 1
local BINARY_OPCODE = 2

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
        local co = coroutine.create(function()
            self._write({ opcode = TEXT_OPCODE, payload = text })
        end)
        local ok, err = coroutine.resume(co)
        if not ok then
            self:emit("error", err)
        end
    end

    -- Sends a raw binary WebSocket frame (opcode 2). Used for the voice
    -- gateway's DAVE/MLS payloads (mls_key_package, mls_commit_welcome,
    -- mls_invalid_commit_welcome), which are not JSON and must not be
    -- sent as a text frame.
    function ws:send_bytes(bytes)
        if self._closed then
            return
        end
        local co = coroutine.create(function()
            self._write({ opcode = BINARY_OPCODE, payload = bytes })
        end)
        local ok, err = coroutine.resume(co)
        if not ok then
            self:emit("error", err)
        end
    end

    function ws:close()
        if self._closed then
            return
        end
        self._closed = true
        local co = coroutine.create(function()
            self._write()
        end)
        coroutine.resume(co)
    end

    function ws:start_reading()
        local co = coroutine.create(function()
            self:emit("open")
            while true do
                local message = self._read()
                if not message then
                    self._closed = true
                    self:emit("close", 1006, "Connection closed without a close frame")
                    return
                end
                if message.opcode == 8 then
                    self._closed = true
                    local payload = message.payload or ""
                    local code = 1005
                    local reason = ""
                    if #payload >= 2 then
                        code = payload:byte(1) * 256 + payload:byte(2)
                        reason = payload:sub(3)
                    end
                    self:emit("close", code, reason)
                    return
                end
                self:emit("message", message.payload, message.opcode == BINARY_OPCODE)
            end
        end)

        local function step(...)
            local ok, err_or_message = coroutine.resume(co, ...)
            if not ok then
                self._closed = true
                self:emit("error", err_or_message)
                self:emit("close", 1006, tostring(err_or_message))
                return
            end
        end

        step()
    end

    return ws
end

return M
