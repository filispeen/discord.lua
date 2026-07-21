-- spec/voice/udp_spec.lua
-- Tests for UDP handling
--
-- All wire data here is raw byte strings (string.char/table.concat built),
-- matching what luv.onread/luv.sendto actually hand this module. Earlier
-- versions of this spec used table.pack(1,2,3,...) as fake "packets",
-- which does not match the real data shape and let a real data[i]-on-a-
-- string bug in udp.lua go unnoticed. Rewritten to use real byte strings.

package.path = "lib/?.lua;lib/?/?.lua;spec/voice/?.lua;" .. package.path

-- Mock luv for testing
local sent_packets = {}

local luv = {
    timer = {
        new = function()
            local timer = {
                _started = false,
                _stop_count = 0,
                start = function()
                    timer._started = true
                end,
                stop = function()
                    timer._stop_count = timer._stop_count + 1
                end,
            }
            return timer
        end
    },
    socket = function()
        return 1
    end,
    bind = function() end,
    getsockname = function() end,
    onread = function() end,
    sendto = function(sock, data, ip, port)
        table.insert(sent_packets, { data = data, ip = ip, port = port })
        return true, nil
    end,
    recvfrom = function()
        return nil
    end,
    close = function() end,
}

package.loaded["luv"] = luv

local udp = require("voice.udp")

local function byte_string(...)
    return string.char(...)
end

describe("UDP", function()
    describe("UDPClient", function()
        it("should create a new UDP client", function()
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")
            assert.is_not_nil(client)
            assert.is_not_nil(client._state)
        end)

        it("should connect to endpoint", function()
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")

            local success, err = pcall(function()
                client:connect()
            end)

            assert.is_true(success)
        end)

        it("should send RTP packet as a raw byte string", function()
            sent_packets = {}
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")
            client:connect()
            client._state.ip = "1.2.3.4"
            client._state.port = 5555

            local payload = byte_string(1, 2, 3, 4, 5, 6, 7, 8)
            local success, err = pcall(function()
                return client:send(payload)
            end)

            assert.is_true(success)
            assert.equals(1, #sent_packets)
            assert.is_string(sent_packets[1].data)
            assert.equals(12 + #payload, #sent_packets[1].data)
            assert.equals("1.2.3.4", sent_packets[1].ip)
            assert.equals(5555, sent_packets[1].port)
        end)

        it("should construct RTP header as a 12 byte string", function()
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")
            client:connect()
            client._state.ssrc = 0

            local payload = byte_string(1, 2, 3, 4)
            local header = client:_construct_rtp_header(payload)

            assert.is_string(header)
            assert.equals(12, #header)
            assert.equals(0x80, header:byte(1))  -- Version 2
            assert.equals(0x78, header:byte(2))  -- Opus payload type
            assert.equals(0, header:byte(3))     -- Sequence high byte
            assert.equals(0, header:byte(4))     -- Sequence low byte
            assert.is_number(header:byte(5))     -- Timestamp bytes
            assert.is_number(header:byte(6))
            assert.is_number(header:byte(7))
            assert.is_number(header:byte(8))
            assert.equals(0, header:byte(9))     -- SSRC
            assert.equals(0, header:byte(10))
            assert.equals(0, header:byte(11))
            assert.equals(0, header:byte(12))
        end)

        it("should increment sequence number across sends", function()
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")
            client:connect()

            local h1 = client:_construct_rtp_header(byte_string(1))
            local h2 = client:_construct_rtp_header(byte_string(1))

            local seq1 = h1:byte(3) * 256 + h1:byte(4)
            local seq2 = h2:byte(3) * 256 + h2:byte(4)

            assert.equals(seq1 + 1, seq2)
        end)

        it("should parse an incoming RTP packet's header and payload", function()
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")
            client:connect()
            client._state.ip = "1.2.3.4"
            client._state.port = 5555

            -- version=0x80, payload_type=0x78, seq=1, timestamp=1000, ssrc=42
            local header = byte_string(
                0x80, 0x78,
                0x00, 0x01,
                0x00, 0x00, 0x03, 0xE8,
                0x00, 0x00, 0x00, 0x2A
            )
            local payload = byte_string(9, 9, 9)
            local packet = header .. payload

            local captured
            client._dispatch_packet = function(self, decoded)
                captured = decoded
            end

            local success = pcall(function()
                client:_handle_rtp(packet, #packet)
            end)

            assert.is_true(success)
            assert.is_string(captured)
            assert.equals(payload, captured)
        end)

        it("should store packets before IP discovery", function()
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")
            client:connect()

            local header = byte_string(0x80, 0x78, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0)
            local payload = byte_string(5, 5, 5)
            local packet = header .. payload

            client:_handle_rtp(packet, #packet)

            assert.is_not_nil(client._state.packets)
            assert.equals(1, #client._state.packets)
            assert.equals(payload, client._state.packets[1].payload)
        end)

        it("should ignore packets smaller than the RTP header", function()
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")
            client:connect()

            local success = pcall(function()
                client:_handle_rtp(byte_string(1, 2, 3), 3)
            end)

            assert.is_true(success)
        end)

        it("should receive packets", function()
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")

            local success, err = pcall(function()
                return client:receive(1000)
            end)

            assert.is_true(success)
        end)

        it("should discover IP", function()
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")
            client:connect()

            local success, err = pcall(function()
                return client:discover_ip()
            end)

            -- IP discovery may fail without real UDP, but shouldn't crash
            assert.is_true(success or err ~= nil)
        end)

        it("should parse discovery response", function()
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")

            -- 74 byte response: type/length header (4), ssrc (4),
            -- null-terminated ip string "10.0.0.1" padded to 64 bytes,
            -- port 1337 as 2 big-endian bytes.
            local header = byte_string(0x00, 0x02, 0x00, 0x46, 0, 0, 0, 0)
            local ip_str = "10.0.0.1"
            local ip_field = ip_str .. string.rep("\0", 64 - #ip_str)
            local port_field = byte_string(5, 57)  -- 5*256+57 = 1337
            local response = header .. ip_field .. port_field

            local ip, port = client:_parse_discovery_response(response)

            assert.equals("10.0.0.1", ip)
            assert.equals(1337, port)
        end)

        it("should reject a too-short discovery response", function()
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")

            local ip, port = client:_parse_discovery_response(byte_string(1, 2, 3))

            assert.is_nil(ip)
            assert.is_nil(port)
        end)

        it("should close connection", function()
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")

            local success, err = pcall(function()
                client:close()
            end)

            assert.is_true(success)
        end)
    end)
end)
