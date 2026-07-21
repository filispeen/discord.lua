-- lib/voice/udp.lua
-- UDP socket handling for voice audio
--
-- Public Contract:
--   UDPClient:new(endpoint, token) - Create UDP client
--   udp:connect() - Connect to voice endpoint
--   udp:send(payload) - Send RTP packet, payload is a raw byte string
--   udp:receive() - Receive RTP packets
--   RTP header construction (12 bytes)
--   IP discovery packet parsing
--
-- Wire format note: everything that touches the network in this module is
-- a raw Lua byte string, never a table of byte-value numbers. luv.onread
-- delivers received datagrams as a string, and luv.sendto expects a
-- string too, so RTP headers and discovery packets are built with
-- string.char()/table.concat() into strings rather than as number arrays.

local luv = require("luv")

local UDPClient = {
    _state = {
        connected = false,
        endpoint = nil,
        token = nil,
        local_port = nil,
        ip = nil,
        port = nil,
        buffer = nil,
        read_timer = nil,
    },
}

-- Create new UDP client
function UDPClient.new(endpoint, token)
    local self = {
        _state = {
            connected = false,
            endpoint = endpoint,
            token = token,
            local_port = nil,
            ip = nil,
            port = nil,
            buffer = nil,
            read_timer = nil,
            sequence = 0,
            ssrc = 0,
        },
    }
    setmetatable(self, { __index = UDPClient })
    return self
end

-- Connect to voice endpoint
function UDPClient:connect()
    local state = self._state

    -- Parse endpoint URL
    local endpoint = state.endpoint
    local host, port_str = endpoint:match("([^:]+):(%d+)$")

    if not host or not port_str then
        error("Invalid endpoint format: " .. endpoint)
    end

    local port = tonumber(port_str)

    -- Create UDP socket
    local sock, err = luv.socket(luv.AF_INET, luv.SOCK_DGRAM)
    if not sock then
        error("Failed to create UDP socket: " .. tostring(err))
    end

    -- Bind to local port
    local local_port = 0  -- Let OS assign
    luv.bind(sock, "0.0.0.0", local_port)

    if luv.getsockname(sock, nil, local_port) then
        error("Failed to get local port: " .. tostring(luv.getsockname(sock)))
    end

    state.local_port = local_port
    state.udp = sock

    -- Start reading packets
    self:read_loop(sock, 1000)

    state.connected = true
    return self
end

-- Read loop for incoming packets
function UDPClient:read_loop(sock, buffer_size)
    self._state.buffer = buffer_size or 2048

    luv.onread(sock, function(n, data)
        if n <= 0 then
            return
        end

        -- Handle RTP packet
        self:_handle_rtp(data, n)
    end)
end

-- Parse a 12 byte RTP header from a raw byte string
local function parse_rtp_header(data)
    local b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12 = data:byte(1, 12)

    return {
        version = math.floor(b1 / 64) % 4,
        padding = math.floor(b1 / 32) % 2 == 1,
        marker = math.floor(b2 / 128) % 2 == 1,
        payload_type = b2 % 128,
        sequence = b3 * 256 + b4,
        timestamp = b5 * 16777216 + b6 * 65536 + b7 * 256 + b8,
        ssrc = b9 * 16777216 + b10 * 65536 + b11 * 256 + b12,
    }
end

-- Handle incoming RTP packet
function UDPClient:_handle_rtp(data, n)
    local state = self._state

    if #data < 12 then
        return  -- Too small for RTP header
    end

    local rtp_header = parse_rtp_header(data)

    -- Calculate payload bounds
    local payload_start = 13  -- 1-indexed, first byte after the 12 byte header
    local payload_end = n

    if rtp_header.padding then
        local padding_length = data:byte(n)
        payload_end = n - padding_length
    end

    local payload = data:sub(payload_start, payload_end)

    -- Dispatch to packet decoder
    if state.ip and state.port then
        local decoded = self:_decode_packet(rtp_header, payload)
        if decoded then
            self:_dispatch_packet(decoded)
        end
    else
        -- IP not discovered yet, store for later
        local stored = {
            header = rtp_header,
            payload = payload,
            timestamp = os.time() * 1000,
        }
        if not state.packets then
            state.packets = {}
        end
        table.insert(state.packets, stored)
    end
end

-- Decode RTP packet (strip header, decrypt if a decrypt callback is set)
function UDPClient:_decode_packet(rtp_header, payload)
    -- For now, just return payload. Decryption is wired in separately
    -- once a secret_key is available (see VoiceGateway:send_session_description).
    return payload
end

-- Dispatch packet to voice client
function UDPClient:_dispatch_packet(packet)
    -- Emit event for packet received
    -- This would be dispatched to the client
end

-- Send RTP packet. payload must be a raw byte string.
function UDPClient:send(payload)
    local state = self._state

    if not state.ip or not state.port then
        error("Not connected: IP and port not discovered")
    end

    if not state.udp then
        error("UDP socket not initialized")
    end

    local rtp_header = self:_construct_rtp_header(payload)
    local full_packet = rtp_header .. payload

    local success, err = luv.sendto(state.udp, full_packet, state.ip, state.port)
    if not success then
        error("Failed to send UDP packet: " .. tostring(err))
    end

    return true
end

-- Construct RTP header (12 bytes), returned as a raw byte string
function UDPClient:_construct_rtp_header(payload)
    local state = self._state

    local version_flags = 0x80  -- Version 2, no padding, no extension, no CSRC
    local payload_type = 0x78   -- Marker bit 0, payload type 120 (Opus)

    local seq = state.sequence or 0
    state.sequence = (seq + 1) % 65536

    local timestamp = math.floor(os.clock() * 48000) % 4294967296
    local ssrc = state.ssrc or 0

    return string.char(
        version_flags,
        payload_type,
        math.floor(seq / 256) % 256,
        seq % 256,
        math.floor(timestamp / 16777216) % 256,
        math.floor(timestamp / 65536) % 256,
        math.floor(timestamp / 256) % 256,
        timestamp % 256,
        math.floor(ssrc / 16777216) % 256,
        math.floor(ssrc / 65536) % 256,
        math.floor(ssrc / 256) % 256,
        ssrc % 256
    )
end

-- Receive RTP packets (blocking or non-blocking)
function UDPClient:receive(timeout_ms)
    local state = self._state

    if not state.udp then
        return nil, "UDP socket not initialized"
    end

    local sock = state.udp

    -- Create timeout timer
    if self._state.read_timer then
        luv.timer:stop(self._state.read_timer)
    end

    local read_timer = luv.timer:new()
    read_timer:start(0, 0, function()
        if self._state.buffer then
            -- Emit timeout event
            self:_emit_timeout()
        end
    end)

    state.read_timer = read_timer

    -- Read from socket
    local data, addr = luv.recvfrom(sock)

    if not data then
        return nil, "No data received"
    end

    return data
end

-- Emit timeout event
function UDPClient:_emit_timeout()
    -- Emit timeout event to client
end

-- Discover IP address (UDP discovery)
function UDPClient:discover_ip()
    local state = self._state

    -- Discovery packet: 74 bytes total.
    -- Byte 1-2: packet type (0x1 = request)
    -- Byte 3-4: packet length (70)
    -- Byte 5-8: SSRC
    -- Byte 9-72: address (zero filled for a request)
    -- Byte 73-74: port (zero filled for a request)
    local ssrc = state.ssrc or 0
    local header = string.char(
        0x00, 0x01,
        0x00, 0x46,
        math.floor(ssrc / 16777216) % 256,
        math.floor(ssrc / 65536) % 256,
        math.floor(ssrc / 256) % 256,
        ssrc % 256
    )
    local padding = string.rep("\0", 66)
    local discovery_packet = header .. padding

    local success, err = luv.sendto(
        state.udp,
        discovery_packet,
        state.ip,
        state.port
    )

    if not success then
        return false, "Failed to send discovery packet: " .. tostring(err)
    end

    -- Wait for response
    local timeout = 1000  -- 1 second
    local start = os.time() * 1000

    while (os.time() * 1000) - start < timeout do
        local data, addr = luv.recvfrom(state.udp)

        if data then
            -- Parse response
            local ip, port = self:_parse_discovery_response(data)
            if ip and port then
                state.ip = ip
                state.port = port
                return true, "IP discovered: " .. ip .. ":" .. port
            end
        end

        -- Wait a bit before next attempt
        luv.sleep(0.05)  -- 50ms
    end

    return false, "Timeout waiting for discovery response"
end

-- Parse discovery response (raw byte string, 74 bytes)
-- Byte 1-4: header (type + length)
-- Byte 5-8: SSRC
-- Byte 9-72: null terminated IP address string
-- Byte 73-74: port (big endian)
function UDPClient:_parse_discovery_response(data)
    if #data < 74 then
        return nil, nil
    end

    local ip_bytes = { data:byte(9, 72) }
    local ip_chars = {}
    for _, b in ipairs(ip_bytes) do
        if b == 0 then
            break
        end
        table.insert(ip_chars, string.char(b))
    end
    local ip = table.concat(ip_chars)

    local port_hi, port_lo = data:byte(73, 74)
    local port = port_hi * 256 + port_lo

    if ip == "" then
        return nil, nil
    end

    return ip, port
end

-- Close UDP connection
function UDPClient:close()
    local state = self._state

    if state.read_timer then
        luv.timer:stop(state.read_timer)
        state.read_timer = nil
    end

    if state.udp then
        luv.close(state.udp)
        state.udp = nil
    end

    state.connected = false
    state.ip = nil
    state.port = nil
    state.buffer = nil

    return true
end

local M = {
    UDPClient = UDPClient,
}

return M
