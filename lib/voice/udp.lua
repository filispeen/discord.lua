-- lib/voice/udp.lua
-- UDP socket handling for voice audio
--
-- Public Contract:
--   UDPClient:new(endpoint, token) - Create UDP client
--   udp:connect() - Connect to voice endpoint
--   udp:send(packet) - Send RTP packet
--   udp:receive() - Receive RTP packets
--   RTP header construction (12 bytes)
--   IP discovery packet parsing

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
        },
    }
    setmetatable(self, UDPClient)
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

-- Handle incoming RTP packet
function UDPClient:_handle_rtp(data, n)
    local state = self._state

    if #data < 12 then
        return  -- Too small for RTP header
    end

    -- Parse RTP header
    local rtp_header = {
        version = (data[1] >> 6) & 0x03,
        padding = data[1] & 0x01,
        marker = data[2] & 0x01,
        padding_length = 0,
        sequence = 0,
        timestamp = 0,
        ssrc = 0,
    }

    -- Extract RTP header fields
    rtp_header.sequence = (data[3] >> 2) & 0x0FFF
    rtp_header.timestamp = data[4] * 16777216 + data[5] * 65536 + data[6] * 256 + data[7]
    rtp_header.ssrc = data[8] * 16777216 + data[9] * 65536 + data[10] * 256 + data[11]

    -- Calculate payload size
    local payload_start = 12
    if rtp_header.padding then
        rtp_header.padding_length = data[n - 1]
        payload_start = n - rtp_header.padding_length
    end

    local payload = table.pack(data, payload_start)

    -- Dispatch to packet decoder
    if state.ip and state.port then
        -- Send to packet decoder
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

-- Decode RTP packet (strip header)
function UDPClient:_decode_packet(rtp_header, payload)
    -- For now, just return payload
    return payload
end

-- Dispatch packet to voice client
function UDPClient:_dispatch_packet(packet)
    -- Emit event for packet received
    -- This would be dispatched to the client
end

-- Send RTP packet
function UDPClient:send(packet)
    local state = self._state

    if not state.ip or not state.port then
        error("Not connected: IP and port not discovered")
    end

    if not state.udp then
        error("UDP socket not initialized")
    end

    -- Construct RTP header
    local rtp_header = self:_construct_rtp_header(packet)

    -- Combine header and payload
    local full_packet = {}
    for i = 1, 12 do
        table.insert(full_packet, rtp_header[i])
    end
    for i = 1, #packet do
        table.insert(full_packet, packet[i])
    end

    -- Send via UDP socket
    local success, err = luv.sendto(state.udp, table.concat(full_packet), state.ip, state.port)
    if not success then
        error("Failed to send UDP packet: " .. tostring(err))
    end

    return true
end

-- Construct RTP header (12 bytes)
function UDPClient:_construct_rtp_header(payload)
    local header = {}

    -- Version: 2 bits
    header[1] = 0x80  -- Version 2, no padding

    -- Payload type: 1 byte (Opus is typically 111 = 0x6F)
    header[2] = 0x7F  -- Payload type for Opus

    -- Sequence number: 2 bytes
    local seq = self._state.sequence or 0
    header[3] = seq >> 8
    header[4] = seq & 0xFF
    self._state.sequence = (seq + 1) % 65536

    -- Timestamp: 4 bytes
    local timestamp = os.time() * 1000  -- Milliseconds
    header[5] = (timestamp >> 24) & 0xFF
    header[6] = (timestamp >> 16) & 0xFF
    header[7] = (timestamp >> 8) & 0xFF
    header[8] = timestamp & 0xFF

    -- SSRC: 4 bytes (Synchronized Source ID)
    local ssrc = self._state.ssrc or 0
    header[9] = (ssrc >> 24) & 0xFF
    header[10] = (ssrc >> 16) & 0xFF
    header[11] = (ssrc >> 8) & 0xFF
    header[12] = ssrc & 0xFF

    return header
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

    -- Send discovery packet to voice server
    -- This is a UDP packet with specific format
    local discovery_packet = {}

    -- First 8 bytes: reserved (set to 0)
    for i = 1, 8 do
        table.insert(discovery_packet, 0)
    end

    -- Next 70 bytes: random/padding (set to 0xFF)
    for i = 1, 70 do
        table.insert(discovery_packet, 0xFF)
    end

    -- Send discovery packet
    local success, err = luv.sendto(
        state.udp,
        table.concat(discovery_packet),
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

-- Parse discovery response
function UDPClient:_parse_discovery_response(data)
    -- Discord discovery response format:
    -- First 8 bytes: reserved
    -- Next 4 bytes: port (big endian)
    -- Next 4 bytes: flags (big endian)
    -- Rest: random

    if #data < 12 then
        return nil, nil
    end

    local port = data[9] * 16777216 + data[10] * 65536 + data[11] * 256 + data[12]
    local ip = data[13] .. "." .. data[14] .. "." .. data[15] .. "." .. data[16]

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
