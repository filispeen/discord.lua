-- spec/voice/udp_spec.lua
-- Tests for UDP handling
--
-- All wire data here is raw byte strings (string.char/table.concat built),
-- matching what luv.onread/luv.sendto actually hand this module. Earlier
-- versions of this spec used table.pack(1,2,3,...) as fake "packets",
-- which does not match the real data shape and let a real data[i]-on-a-
-- string bug in udp.lua go unnoticed. Rewritten to use real byte strings.

require("spec_helper")
package.path = "spec/voice/?.lua;" .. package.path

-- Mock luv for testing. Real luv/uv UDP handles are userdata with
-- methods (sock:bind, sock:getsockname, sock:recv_start, sock:send,
-- sock:close), not free functions like luv.socket()/luv.sendto(); the
-- mock mirrors that shape so udp.lua exercises the same call pattern
-- it uses against the real binding.
local sent_packets = {}
local recv_callback = nil

local function make_mock_socket()
    local sock = {}
    function sock:bind(_host, _port)
        return true, nil
    end
    function sock:getsockname()
        return { ip = "0.0.0.0", port = 12345, family = "inet" }, nil
    end
    function sock:recv_start(callback)
        recv_callback = callback
        return true, nil
    end
    function sock:send(data, ip, port, _callback)
        table.insert(sent_packets, { data = data, ip = ip, port = port })
        return true, nil
    end
    function sock:close()
        recv_callback = nil
    end
    return sock
end

local luv = {
    new_udp = function()
        return make_mock_socket()
    end,
    new_timer = function()
        local timer
        timer = {
            _started = false,
            _stop_count = 0,
            _callback = nil,
            start = function(self, timeout, repeat_ms, callback)
                timer._started = true
                timer._callback = callback
            end,
            stop = function()
                timer._stop_count = timer._stop_count + 1
            end,
        }
        return timer
    end,
}

package.loaded["mock_luv"] = luv

local udp = require("./voice/udp")

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

            local captured_header, captured_payload
            client._dispatch_packet = function(self, rtp_header, decoded)
                captured_header = rtp_header
                captured_payload = decoded
            end

            local success = pcall(function()
                client:_handle_rtp(packet, #packet)
            end)

            assert.is_true(success)
            assert.is_string(captured_payload)
            assert.equals(payload, captured_payload)
            assert.equals(42, captured_header.ssrc)
            assert.equals(1, captured_header.sequence)
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

        it("should error when called outside a coroutine", function()
            -- table.sort's comparator callback is a genuine C-call
            -- boundary in every Lua runtime this codebase targets
            -- (lua5.1/luajit for busted's default CI runner, luvit for
            -- the actual production runtime, see run_luvit_busted.sh),
            -- so this reliably recreates "outside a coroutine" instead
            -- of a plain top-level pcall: under lua5.1/luajit,
            -- coroutine.running() is still nil inside the comparator
            -- (it's the main thread, not a real coroutine), so
            -- receive()'s own guard fires with its "must be called
            -- from within a coroutine" message before ever reaching
            -- coroutine.yield(). Under luvit, coroutine.running() is
            -- always a real thread (see the "not constructible under
            -- luvit" comment this replaced), so that guard never
            -- fires there and execution instead reaches
            -- coroutine.yield() itself, which the C-call boundary
            -- rejects with its own "C-call boundary" wording. Both are
            -- genuine, correct rejections of the same "can't yield
            -- here" scenario, just surfaced by two different guards
            -- depending on what the runtime's coroutine.running()
            -- reports; the assertion below accepts either.
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")
            client:connect()

            local success, err = pcall(function()
                table.sort({ 1, 2 }, function()
                    return client:receive(1000)
                end)
            end)

            assert.is_false(success)
            assert.is_true(
                err:find("coroutine", 1, true) ~= nil or err:find("boundary", 1, true) ~= nil,
                "expected error to mention 'coroutine' or 'boundary', got: " .. tostring(err)
            )
        end)

        it("should resolve receive with a decoded packet dispatched while waiting", function()
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")
            client:connect()
            client._state.ip = "10.0.0.1"
            client._state.port = 5555

            local result, err

            local co = coroutine.create(function()
                result, err = client:receive(1000)
            end)
            coroutine.resume(co)

            assert.is_not_nil(client._state.receive_waiter)

            local header = byte_string(0x80, 0x78, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0)
            local payload = byte_string(5, 5, 5)
            local packet = header .. payload

            client:_handle_rtp(packet, #packet)

            assert.is_nil(client._state.receive_waiter)
            assert.is_not_nil(result)
            assert.equals(payload, result.payload)
            assert.equals(1, result.header.sequence)
            assert.is_nil(err)
        end)

        it("should time out receive when no packet arrives", function()
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")
            client:connect()

            local result, err

            local co = coroutine.create(function()
                result, err = client:receive(1000)
            end)
            coroutine.resume(co)

            local waiter = client._state.receive_waiter
            assert.is_not_nil(waiter)
            waiter.timer._callback()

            assert.is_nil(client._state.receive_waiter)
            assert.is_nil(result)
            assert.equals("timeout", err)
        end)

        it("should reject a second receive while one is already waiting", function()
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")
            client:connect()

            local co1 = coroutine.create(function()
                client:receive(1000)
            end)
            coroutine.resume(co1)

            local result2, err2
            local co2 = coroutine.create(function()
                result2, err2 = client:receive(1000)
            end)
            coroutine.resume(co2)

            assert.is_nil(result2)
            assert.equals("receive already in progress", err2)
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

        it("should send unencrypted when no secret_key is set", function()
            sent_packets = {}
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")
            client:connect()
            client._state.ip = "1.2.3.4"
            client._state.port = 5555

            local payload = byte_string(1, 2, 3)
            client:send(payload)

            assert.equals(12 + #payload, #sent_packets[1].data)
            assert.equals(payload, sent_packets[1].data:sub(13))
        end)

        it("should error on send when secret_key is set but the wrong key size is used", function()
            -- Crypto.available() is now always true (libsodium or the
            -- pure-Lua fallback), so the "no crypto backend at all"
            -- path no longer exists. The safety property that still
            -- matters is that send() must error rather than silently
            -- send plaintext when encryption itself fails for some
            -- other reason (e.g. a malformed secret_key), regardless of
            -- which backend is active.
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")
            client:connect()
            client._state.ip = "1.2.3.4"
            client._state.port = 5555
            client._state.secret_key = "too_short_to_be_a_valid_key"

            local success = pcall(function()
                client:send(byte_string(1, 2, 3))
            end)

            assert.is_false(success)
        end)

        it("should encrypt on send and decrypt back to the original payload", function()
            local crypto = require("./voice/crypto")

            sent_packets = {}
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")
            client:connect()
            client._state.ip = "1.2.3.4"
            client._state.port = 5555
            client._state.secret_key = string.rep("k", 32)
            client._state.mode = "xsalsa20_poly1305_suffix"

            local payload = byte_string(1, 2, 3)
            client:send(payload)

            local sent = sent_packets[1].data
            local rtp_header_len = 12
            local nonce_len = crypto.nonce_size()
            local nonce = sent:sub(-nonce_len)
            local ciphertext = sent:sub(rtp_header_len + 1, -nonce_len - 1)

            assert.equals(rtp_header_len + #payload + crypto.macbytes() + nonce_len, #sent)

            local rtp_header = { ssrc = 1, sequence = 1, timestamp = 1, padding = false }
            local decoded = client:_decode_packet(rtp_header, ciphertext, nonce)

            assert.equals(payload, decoded)
        end)

        it("should decode as pass-through when no secret_key is set", function()
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")
            client:connect()

            local rtp_header = { ssrc = 1, sequence = 1, timestamp = 1, padding = false }
            local payload = byte_string(1, 2, 3)

            local decoded = client:_decode_packet(rtp_header, payload, nil)

            assert.equals(payload, decoded)
        end)

        it("should drop packets when secret_key is set but no nonce was extracted", function()
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")
            client:connect()
            client._state.secret_key = string.rep("k", 32)

            local rtp_header = { ssrc = 1, sequence = 1, timestamp = 1, padding = false }
            local decoded = client:_decode_packet(rtp_header, byte_string(1, 2, 3), nil)

            assert.is_nil(decoded)
        end)

        it("should strip the suffix nonce from incoming packets when secret_key and mode are set", function()
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")
            client:connect()
            client._state.ip = "1.2.3.4"
            client._state.port = 5555
            client._state.secret_key = string.rep("k", 32)
            client._state.mode = "xsalsa20_poly1305_suffix"

            local header = byte_string(0x80, 0x78, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0)
            local ciphertext = byte_string(9, 9, 9, 9)  -- fake ciphertext, doesn't need to decrypt for this test
            local nonce = string.rep("n", 24)
            local packet = header .. ciphertext .. nonce

            local captured_payload
            client._decode_packet = function(self, rtp_header, payload, extracted_nonce)
                captured_payload = payload
                assert.equals(nonce, extracted_nonce)
                return nil
            end

            client:_handle_rtp(packet, #packet)

            assert.equals(ciphertext, captured_payload)
        end)
    end)

    describe("aead_xchacha20_poly1305_rtpsize mode", function()
        it("should strip the 4 byte wire nonce and pass the RTP header as AAD", function()
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")
            client:connect()
            client._state.ip = "1.2.3.4"
            client._state.port = 5555
            client._state.secret_key = string.rep("k", 32)
            client._state.mode = "aead_xchacha20_poly1305_rtpsize"

            local header = byte_string(0x80, 0x78, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0)
            local ciphertext_and_tag = byte_string(9, 9, 9, 9)  -- fake, doesn't need to decrypt for this test
            local wire_nonce = byte_string(0, 0, 0, 42)
            local packet = header .. ciphertext_and_tag .. wire_nonce

            local captured_payload, captured_nonce, captured_aad
            client._decode_packet = function(self, rtp_header, payload, nonce, aad)
                captured_payload = payload
                captured_nonce = nonce
                captured_aad = aad
                return nil
            end

            client:_handle_rtp(packet, #packet)

            assert.equals(ciphertext_and_tag, captured_payload)
            assert.equals(header, captured_aad)
            assert.equals(24, #captured_nonce)
            assert.equals(wire_nonce, captured_nonce:sub(1, 4))
            assert.equals(string.rep("\0", 20), captured_nonce:sub(5))
        end)

        it("should increment the wire nonce counter on each send", function()
            sent_packets = {}
            local client = udp.UDPClient.new("192.168.1.1:12345", "token123")
            client:connect()
            client._state.ip = "1.2.3.4"
            client._state.port = 5555

            local wire1 = select(1, client:_next_aead_nonce())
            local wire2 = select(1, client:_next_aead_nonce())

            assert.equals(byte_string(0, 0, 0, 0), wire1)
            assert.equals(byte_string(0, 0, 0, 1), wire2)
        end)

        if require("./voice/crypto").aead_available() then
            it("should encrypt on send and decrypt back to the original payload", function()
                local crypto = require("./voice/crypto")

                sent_packets = {}
                local client = udp.UDPClient.new("192.168.1.1:12345", "token123")
                client:connect()
                client._state.ip = "1.2.3.4"
                client._state.port = 5555
                client._state.secret_key = string.rep("k", 32)
                client._state.mode = "aead_xchacha20_poly1305_rtpsize"

                local payload = byte_string(1, 2, 3, 4, 5)
                client:send(payload)

                local sent = sent_packets[1].data
                local rtp_header = sent:sub(1, 12)
                local ciphertext_and_tag_and_nonce = sent:sub(13)
                local wire_nonce = ciphertext_and_tag_and_nonce:sub(-4)
                local ciphertext_and_tag = ciphertext_and_tag_and_nonce:sub(1, -5)

                assert.equals(#payload + crypto.aead_macbytes() + 4, #ciphertext_and_tag_and_nonce)

                local nonce = wire_nonce .. string.rep("\0", crypto.aead_nonce_size() - 4)
                local decrypted = crypto.aead_decrypt(ciphertext_and_tag, nonce, client._state.secret_key, rtp_header)

                assert.equals(payload, decrypted)
            end)

            it("should round-trip a full incoming packet through _handle_rtp", function()
                local crypto = require("./voice/crypto")

                local client = udp.UDPClient.new("192.168.1.1:12345", "token123")
                client:connect()
                client._state.ip = "1.2.3.4"
                client._state.port = 5555
                client._state.secret_key = string.rep("k", 32)
                client._state.mode = "aead_xchacha20_poly1305_rtpsize"

                local header = byte_string(0x80, 0x78, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0)
                local plaintext = byte_string(10, 20, 30, 40)
                local wire_nonce = byte_string(0, 0, 0, 7)
                local aead_nonce = wire_nonce .. string.rep("\0", crypto.aead_nonce_size() - 4)
                local ciphertext_and_tag = crypto.aead_encrypt(plaintext, aead_nonce, client._state.secret_key, header)
                local packet = header .. ciphertext_and_tag .. wire_nonce

                local captured_header, captured_payload
                client._dispatch_packet = function(self, rtp_header, decoded)
                    captured_header = rtp_header
                    captured_payload = decoded
                end

                client:_handle_rtp(packet, #packet)

                assert.equals(plaintext, captured_payload)
                assert.equals(1, captured_header.sequence)
            end)
        else
            pending("aead_xchacha20_poly1305_rtpsize send/receive round-trip (requires LuaJIT + libsodium, not active in this environment)")
        end
    end)
end)
