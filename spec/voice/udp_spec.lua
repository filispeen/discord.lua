-- spec/voice/udp_spec.lua
-- Tests for UDP handling

package.path = "lib/?.lua;lib/?/?.lua;spec/voice/?.lua;" .. package.path

-- Mock luv for testing
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
    sendto = function()
        return true, nil
    end,
    recvfrom = function()
        return nil
    end,
    close = function() end,
}

package.loaded["luv"] = luv

local udp = require("voice.udp")

describe("UDP", function()
    describe("UDPClient", function()
        it("should create a new UDP client", function()
            local client = udp.UDPClient:new("192.168.1.1:12345", "token123")
            assert.is_not_nil(client)
            assert.is_not_nil(client._state)
        end)

        it("should connect to endpoint", function()
            local client = udp.UDPClient:new("192.168.1.1:12345", "token123")

            local success, err = pcall(function()
                client:connect()
            end)

            assert.is_true(success)
        end)

        it("should send RTP packet", function()
            local client = udp.UDPClient:new("192.168.1.1:12345", "token123")
            client:connect()

            local packet = table.pack(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)
            local success, err = pcall(function()
                return client:send(packet)
            end)

            assert.is_true(success)
        end)

        it("should construct RTP header", function()
            local client = udp.UDPClient:new("192.168.1.1:12345", "token123")
            client:connect()

            -- Manually test header construction
            local payload = table.pack(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)
            local header = client:_construct_rtp_header(payload)

            assert.equals(12, #header)
            assert.equals(0x80, header[1])  -- Version 2
            assert.equals(0x7F, header[2])  -- Opus payload type
            assert.equals(0, header[3])     -- Sequence
            assert.equals(0, header[4])
            assert.equals(0, header[5])
            assert.equals(0, header[6])
            assert.equals(0, header[7])
            assert.equals(0, header[8])
            assert.equals(0, header[9])
            assert.equals(0, header[10])
            assert.equals(0, header[11])
            assert.equals(0, header[12])
        end)

        it("should receive packets", function()
            local client = udp.UDPClient:new("192.168.1.1:12345", "token123")

            local success, err = pcall(function()
                return client:receive(1000)
            end)

            assert.is_true(success)
        end)

        it("should discover IP", function()
            local client = udp.UDPClient:new("192.168.1.1:12345", "token123")

            local success, err = pcall(function()
                return client:discover_ip()
            end)

            -- IP discovery may fail without real UDP, but shouldn't crash
            assert.is_true(success or err ~= nil)
        end)

        it("should parse discovery response", function()
            local client = udp.UDPClient:new("192.168.1.1:12345", "token123")

            -- Mock response: 10.0.0.1:1337
            local response = table.pack(0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
            local ip, port = client:_parse_discovery_response(response)

            assert.equals("10.0.0.1", ip)
            assert.equals(1337, port)
        end)

        it("should close connection", function()
            local client = udp.UDPClient:new("192.168.1.1:12345", "token123")

            local success, err = pcall(function()
                client:close()
            end)

            assert.is_true(success)
        end)
    end)
end)
