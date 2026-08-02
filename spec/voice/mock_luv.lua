-- spec/voice/mock_luv.lua
-- Mock luv for voice tests

local sockets = {}
local socket_id = 0

local mock_luv = {
    -- new_timer is a top-level function on the real uv module (see
    -- lib/core/luv_compat.lua), not a field under a "timer" table.
    -- Nothing in spec/ currently requires this file directly (each
    -- voice spec keeps its own inline mock_luv), but this is kept
    -- matching the real API rather than the stale timer.new() shape
    -- in case that changes.
    new_timer = function()
        local timer = {
            _started = false,
            _stop_count = 0,
            start = function(self, _delay, _repeat_ms, callback)
                self._started = true
                self.callback = callback
            end,
            stop = function(self)
                self._stop_count = self._stop_count + 1
            end,
        }
        return timer
    end,
    socket = function(type, flags)
        socket_id = socket_id + 1
        sockets[socket_id] = {
            type = type,
            flags = flags,
            data = {},
        }
        return socket_id
    end,
    bind = function(sock, host, port) end,
    getsockname = function(sock, _, port)
        return port
    end,
    onread = function(sock, callback)
        sockets[sock].callback = callback
    end,
    sendto = function(sock, data, ip, port)
        if not data then
            return true, nil
        end
        sockets[sock].data = data
        return true, nil
    end,
    recvfrom = function(sock)
        if sockets[sock].data then
            return sockets[sock].data, nil
        end
        return nil
    end,
    close = function(sock)
        sockets[sock] = nil
    end,
}

return mock_luv
