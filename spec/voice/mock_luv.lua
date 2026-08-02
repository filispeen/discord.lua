-- spec/voice/mock_luv.lua
-- Mock luv for voice tests

local sockets = {}
local socket_id = 0

local mock_luv = {
    timer = {
        -- start() invokes callback synchronously rather than actually
        -- waiting: tests don't care about real timing, only that a
        -- delayed action (e.g. voice_client.lua's leave-then-rejoin on
        -- session_invalidated) eventually happens. once=true skips the
        -- callback on a second start() the way a one-shot uv timer
        -- would after firing once, since some callers (session_description
        -- style repeat timers) call start() only once anyway but this
        -- keeps repeat-timer callers from double-firing if they ever
        -- call start() again on the same mock instance.
        new = function()
            local timer = {
                _started = false,
                _stop_count = 0,
                _stopped = false,
                start = function(self, _delay, _repeat_ms, callback)
                    self._started = true
                    if callback and not self._stopped then
                        callback()
                    end
                end,
                stop = function(self)
                    self._stopped = true
                    self._stop_count = self._stop_count + 1
                end,
            }
            return timer
        end
    },
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
