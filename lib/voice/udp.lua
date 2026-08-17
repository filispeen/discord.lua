-- lib/voice/udp.lua
-- UDP socket handling for voice audio
--
-- Public Contract:
--   UDPClient:new(endpoint, token) - Create UDP client
--   udp:connect() - Connect to voice endpoint
--   udp:send(payload) - Send RTP packet, payload is a raw byte string.
--     Encrypted with udp._state.secret_key if set, per udp._state.mode
--     (aead_xchacha20_poly1305_rtpsize, Discord's current required
--     mode; xsalsa20_poly1305_suffix, legacy, kept for reference only).
--   udp:send_raw(payload) - Send raw bytes straight to the voice
--     server's ip/port with no RTP header and no encryption. Used for
--     UDP keep-alive packets (see VoiceClient's _start_udp_keepalive),
--     not for voice data.
--   udp:receive(timeout_ms) - Receive one decoded RTP packet, coroutine-based
--   udp._state.secret_key - set by VoiceClient after SESSION_DESCRIPTION;
--     when present, _decode_packet decrypts incoming RTP payloads and
--     send() encrypts outgoing ones. When absent, payloads pass through
--     unencrypted (this only happens before the handshake completes).
--   udp._state.mode - encryption mode string from SESSION_DESCRIPTION,
--     selects which nonce placement/AEAD send()/_decode_packet use.
--   RTP header construction (12 bytes)
--   IP discovery packet parsing
--
-- Wire format note: everything that touches the network in this module is
-- a raw Lua byte string, never a table of byte-value numbers. uv's udp
-- recv_start callback delivers received datagrams as a string, and
-- sock:send expects a string too, so RTP headers and discovery packets
-- are built with string.char()/table.concat() into strings rather than
-- as number arrays.
--
-- uv here is the real libuv binding (require("../core/luv_compat")),
-- whose UDP handle is a userdata with methods: uv.new_udp(), then
-- sock:bind(host, port), sock:getsockname(), sock:recv_start(cb),
-- sock:send(data, host, port, cb), sock:close(). This is not the same
-- shape as the old luv.socket()/luv.bind()/luv.sendto() free-function
-- API this file used to assume; that API does not exist on luvit's uv.

local uv = require("../core/luv_compat")
local crypto = require("./crypto")

-- aead_xchacha20_poly1305_rtpsize's wire nonce is a 4 byte big-endian
-- incrementing counter (distinct from the 24 byte XChaCha20 nonce
-- crypto.aead_* actually operates on; see the send()/_handle_rtp nonce
-- construction, which zero-extends this to crypto.aead_nonce_size()).
local RTPSIZE_WIRE_NONCE_SIZE = 4

local UDPClient = {
    _state = {
        connected = false,
        endpoint = nil,
        token = nil,
        local_port = nil,
        remote_ip = nil,
        remote_port = nil,
        ip = nil,
        port = nil,
        buffer = nil,
        receive_waiter = nil,
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
            remote_ip = nil,
            remote_port = nil,
            ip = nil,
            port = nil,
            buffer = nil,
            receive_waiter = nil,
            sequence = 0,
            ssrc = 0,
            nonce_counter = 0,
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
    state.remote_ip = host
    state.remote_port = port

    -- Create UDP socket
    local sock = uv.new_udp()
    if not sock then
        error("Failed to create UDP socket")
    end

    -- Bind to local port, letting the OS assign one
    local bind_ok, bind_err = sock:bind("0.0.0.0", 0)
    if not bind_ok then
        error("Failed to bind UDP socket: " .. tostring(bind_err))
    end

    local name, name_err = sock:getsockname()
    if not name then
        error("Failed to get local port: " .. tostring(name_err))
    end

    state.local_port = name.port
    state.udp = sock

    -- Start reading packets
    self:read_loop(sock)

    state.connected = true
    return self
end

-- Read loop for incoming packets
function UDPClient:read_loop(sock)
    self._state.buffer = 2048

    local ok, err = sock:recv_start(function(read_err, data, _addr)
        if read_err then
            return
        end
        if not data then
            return  -- nil data with no error is just an empty read, not a packet
        end

        -- Handle RTP packet
        self:_handle_rtp(data, #data)
    end)

    if not ok then
        error("Failed to start UDP recv: " .. tostring(err))
    end
end

-- Parse the fixed 12 byte RTP header from a raw byte string. This only
-- reads the fixed portion (version/flags through SSRC); CSRC identifiers
-- and any RTP header extension, if present, follow immediately after and
-- are handled separately by _handle_rtp (see unencrypted_header_size
-- there), since their presence/length isn't knowable until these fields
-- are parsed.
local function parse_rtp_header(data)
    local b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12 = data:byte(1, 12)

    return {
        version = math.floor(b1 / 64) % 4,
        padding = math.floor(b1 / 32) % 2 == 1,
        extension = math.floor(b1 / 16) % 2 == 1,
        csrc_count = b1 % 16,
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

    -- IP discovery response: type 0x0002, distinct from any RTP packet
    -- (RTP's first byte always has the version bits set, 0x80+, so this
    -- can't collide with a real RTP header). Route it to discover_ip's
    -- waiter instead of treating it as RTP.
    if state.discovery_waiter and n >= 74 and data:byte(1) == 0x00 and data:byte(2) == 0x02 then
        local ip, port = self:_parse_discovery_response(data)
        if ip and port then
            state.ip = ip
            state.port = port
        end
        self:_resolve_discovery_waiter(ip, port)
        return
    end

    if #data < 12 then
        return  -- Too small for RTP header
    end

    local rtp_header = parse_rtp_header(data)

    -- With RTP-size AEAD modes, the unencrypted (authenticated but not
    -- encrypted) portion of the header is not always exactly 12 bytes:
    -- per Discord's docs, it also includes any CSRC identifiers and, if
    -- the extension bit is set, the 4 byte one-byte-extension preamble
    -- (0xBEDE + length; the individual extension elements themselves are
    -- encrypted along with the RTP payload, not part of this preamble).
    -- Getting this wrong means both the AAD used for decryption and the
    -- payload_start offset are wrong, which makes every AEAD packet fail
    -- to authenticate even though secret_key/nonce/mode are all correct.
    local unencrypted_header_size = 12 + rtp_header.csrc_count * 4
    local extension_size = 0
    if rtp_header.extension then
        if #data < unencrypted_header_size + 4 then
            return
        end

        local extension_profile_hi, extension_profile_lo, extension_length_hi, extension_length_lo =
            data:byte(unencrypted_header_size + 1, unencrypted_header_size + 4)
        if extension_profile_hi == nil or extension_profile_lo == nil or
            extension_length_hi == nil or extension_length_lo == nil then
            return
        end

        local extension_profile = extension_profile_hi * 256 + extension_profile_lo
        if extension_profile ~= 0xBEDE then
            return
        end

        extension_size = (extension_length_hi * 256 + extension_length_lo) * 4
        unencrypted_header_size = unencrypted_header_size + 4
    end

    if #data < unencrypted_header_size + extension_size then
        return
    end

    -- Calculate payload bounds
    local payload_start = unencrypted_header_size + 1  -- 1-indexed, first byte after the unencrypted header
    local payload_end = n

    if rtp_header.padding then
        local padding_length = data:byte(n)
        payload_end = n - padding_length
    end

    -- aead_xchacha20_poly1305_rtpsize (Discord's current required mode)
    -- appends a 4 byte big-endian counter nonce after the encrypted
    -- payload (ciphertext + 16 byte Poly1305 tag). The legacy
    -- xsalsa20_poly1305_suffix mode appended a 24 byte random nonce
    -- instead; both are stripped here before treating the rest as
    -- ciphertext, kept only for reference since Discord discontinued
    -- xsalsa20_poly1305_suffix in November 2024 (see enums.SUPPORTED_MODES).
    local nonce = nil
    if state.secret_key and state.mode == "aead_xchacha20_poly1305_rtpsize" then
        if payload_end - payload_start + 1 < RTPSIZE_WIRE_NONCE_SIZE then
            return  -- Too small to contain the wire nonce
        end
        local wire_nonce = data:sub(payload_end - RTPSIZE_WIRE_NONCE_SIZE + 1, payload_end)
        nonce = wire_nonce .. string.rep("\0", crypto.aead_nonce_size() - RTPSIZE_WIRE_NONCE_SIZE)
        payload_end = payload_end - RTPSIZE_WIRE_NONCE_SIZE
    elseif state.secret_key and state.mode == "xsalsa20_poly1305_suffix" then
        if payload_end - payload_start + 1 < crypto.nonce_size() then
            return  -- Too small to contain a suffix nonce
        end
        nonce = data:sub(payload_end - crypto.nonce_size() + 1, payload_end)
        payload_end = payload_end - crypto.nonce_size()
    end

    local payload = data:sub(payload_start, payload_end)

    -- AAD for the rtpsize AEAD mode is the unencrypted header bytes
    -- (fixed header + CSRCs + extension preamble if present, see
    -- unencrypted_header_size above); the legacy suffix mode has no AAD
    -- concept.
    local aad = nil
    if state.mode == "aead_xchacha20_poly1305_rtpsize" then
        aad = data:sub(1, unencrypted_header_size)
    end

    -- Dispatch to packet decoder
    if state.ip and state.port then
        local decoded = self:_decode_packet(rtp_header, payload, nonce, aad, extension_size)
        if decoded then
            self:_dispatch_packet(rtp_header, decoded)
        end
    else
        -- IP not discovered yet, store for later
        local stored = {
            header = rtp_header,
            payload = payload,
            nonce = nonce,
            aad = aad,
            timestamp = os.time() * 1000,
            extension_size = extension_size,
        }
        if not state.packets then
            state.packets = {}
        end
        table.insert(state.packets, stored)
    end
end

-- Decode RTP packet: decrypt the payload if a secret_key is set, otherwise
-- pass it through unchanged. nonce is the nonce extracted by _handle_rtp
-- (24 bytes zero-extended from the rtpsize mode's 4 byte wire counter,
-- or the legacy suffix mode's 24 byte random nonce); nil if no secret_key
-- or mode is set. aad is only used by the AEAD rtpsize mode.
function UDPClient:_decode_packet(_rtp_header, payload, nonce, aad, extension_size)
    local state = self._state

    if not state.secret_key then
        return payload
    end

    if not nonce then
        -- secret_key is set but we have no nonce (mode mismatch or not
        -- yet supported), can't decrypt; drop rather than pass ciphertext
        -- through as if it were plaintext.
        return nil
    end

    local plaintext
    if state.mode == "aead_xchacha20_poly1305_rtpsize" then
        plaintext = crypto.aead_decrypt(payload, nonce, state.secret_key, aad)
    else
        plaintext = crypto.decrypt(payload, nonce, state.secret_key)
    end
    if not plaintext then
        return nil
    end

    if extension_size and extension_size > 0 then
        if #plaintext < extension_size then
            return nil
        end
        plaintext = plaintext:sub(extension_size + 1)
    end

    return plaintext
end

-- Dispatch packet to voice client. self._state.on_packet, if set by the
-- owner (see VoiceClient:setup), is called as on_packet(rtp_header, payload)
-- with the decrypted/decoded payload for SSRC->user_id routing.
--
-- Also feeds UDPClient:receive()'s waiter queue: any coroutine parked in
-- receive() via _wait_for_packet is resumed here with the same decoded
-- packet, in addition to (not instead of) the on_packet callback above.
function UDPClient:_dispatch_packet(rtp_header, payload)
    local state = self._state
    if state.on_packet then
        state.on_packet(rtp_header, payload)
    end
    self:_resolve_waiter(rtp_header, payload)
end

-- Resume the coroutine parked in receive(), if any, with a decoded packet.
-- No-op if nothing is currently waiting (e.g. voice consumed purely via
-- on_packet).
function UDPClient:_resolve_waiter(rtp_header, payload)
    local state = self._state
    local waiter = state.receive_waiter
    if not waiter then
        return
    end
    state.receive_waiter = nil
    if waiter.timer then
        waiter.timer:stop()
    end
    coroutine.resume(waiter.co, { header = rtp_header, payload = payload }, nil)
end

-- Send RTP packet. payload must be a raw byte string. If udp._state.
-- secret_key is set, payload is encrypted per udp._state.mode:
--   aead_xchacha20_poly1305_rtpsize (Discord's current required mode):
--     AEAD-encrypted with the RTP header as additional authenticated
--     data, then a 4 byte big-endian incrementing counter (the "wire
--     nonce") is appended after the ciphertext+tag. The 24 byte nonce
--     crypto.aead_encrypt actually needs is this counter zero-extended;
--     see _next_aead_nonce.
--   xsalsa20_poly1305_suffix (legacy, discontinued by Discord Nov 2024,
--     kept only for reference/tests): a fresh random 24 byte nonce is
--     appended after the ciphertext instead.
function UDPClient:send(payload)
    local state = self._state

    if not state.ip or not state.port then
        error("Not connected: IP and port not discovered")
    end

    if not state.udp then
        error("UDP socket not initialized")
    end

    local rtp_header = self:_construct_rtp_header(payload)
    local body = payload

    if state.secret_key then
        if state.mode == "aead_xchacha20_poly1305_rtpsize" then
            local wire_nonce, nonce = self:_next_aead_nonce()

            local ciphertext, err = crypto.aead_encrypt(payload, nonce, state.secret_key, rtp_header)
            if not ciphertext then
                error("Failed to encrypt payload: " .. tostring(err))
            end

            body = ciphertext .. wire_nonce
        else
            local nonce, nerr = crypto.random_nonce()
            if not nonce then
                error("Failed to generate nonce: " .. tostring(nerr))
            end

            local ciphertext, err = crypto.encrypt(payload, nonce, state.secret_key)
            if not ciphertext then
                error("Failed to encrypt payload: " .. tostring(err))
            end

            body = ciphertext .. nonce
        end
    end

    local full_packet = rtp_header .. body

    local success, err = state.udp:send(full_packet, state.ip, state.port)
    if not success then
        error("Failed to send UDP packet: " .. tostring(err))
    end

    return true
end

-- Sends raw bytes directly to the voice server's discovered ip/port,
-- with no RTP header, no encryption, and no interpretation of the
-- payload. Used for UDP keep-alive: unlike send(), which only fires
-- when the bot is actively transmitting encoded voice, a bot that is
-- purely recording/listening never calls send() at all, so nothing
-- keeps the outbound UDP flow alive. Discord's SFU (and any NAT this
-- traffic passes through, e.g. WSL2's virtual networking) can stop
-- forwarding inbound audio to a client whose socket has gone quiet in
-- the other direction; real Discord clients avoid this by always
-- maintaining some outbound UDP traffic while connected. Mirrors
-- pycord's UDPKeepAlive, which sends a raw incrementing 8-byte counter
-- (no RTP framing) every 5 seconds while a receive-side reader is
-- active. Payload should be small; content is not interpreted by
-- Discord's voice server, only its arrival matters.
function UDPClient:send_raw(payload)
    local state = self._state

    if not state.ip or not state.port then
        error("Not connected: IP and port not discovered")
    end

    if not state.udp then
        error("UDP socket not initialized")
    end

    local success, err = state.udp:send(payload, state.ip, state.port)
    if not success then
        error("Failed to send raw UDP packet: " .. tostring(err))
    end

    return true
end

-- Returns (wire_nonce, aead_nonce) for the next outgoing aead_xchacha20_
-- poly1305_rtpsize packet: wire_nonce is the 4 byte big-endian counter
-- that actually goes on the wire (appended after the ciphertext, see
-- send()), aead_nonce is that same counter zero-extended to the 24
-- bytes crypto.aead_encrypt requires. The counter increments on every
-- call and wraps at 2^32, matching the "32-bit incremental integer"
-- nonce Discord's docs specify for this mode.
function UDPClient:_next_aead_nonce()
    local state = self._state
    local counter = state.nonce_counter or 0

    local wire_nonce = string.char(
        math.floor(counter / 16777216) % 256,
        math.floor(counter / 65536) % 256,
        math.floor(counter / 256) % 256,
        counter % 256
    )

    state.nonce_counter = (counter + 1) % 4294967296

    local aead_nonce = wire_nonce .. string.rep("\0", crypto.aead_nonce_size() - RTPSIZE_WIRE_NONCE_SIZE)
    return wire_nonce, aead_nonce
end

-- Construct RTP header (12 bytes), returned as a raw byte string
function UDPClient:_construct_rtp_header(_payload)
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

-- Receive a decoded RTP packet, waiting up to timeout_ms if none is
-- already queued. Must be called from inside a coroutine: real incoming
-- packets only ever arrive via the onread callback (see read_loop /
-- _handle_rtp), so there is no way to receive one without yielding back
-- to the event loop while we wait.
--
-- Returns:
--   packet, nil          - packet is { header = rtp_header, payload = ... }
--   nil, "timeout"        - timeout_ms elapsed with nothing received
--   nil, "no data received" - socket not initialized / not connected
--
-- timeout_ms defaults to 1000 if omitted.
function UDPClient:receive(timeout_ms)
    local state = self._state

    if not state.udp then
        return nil, "no data received"
    end

    if state.receive_waiter then
        return nil, "receive already in progress"
    end

    local co = coroutine.running()
    if not co then
        error("UDPClient:receive must be called from within a coroutine")
    end

    timeout_ms = timeout_ms or 1000

    local timer = uv.new_timer()
    state.receive_waiter = { co = co, timer = timer }

    timer:start(timeout_ms, 0, function()
        local waiter = state.receive_waiter
        if not waiter or waiter.co ~= co then
            return
        end
        state.receive_waiter = nil
        coroutine.resume(co, nil, "timeout")
    end)

    return coroutine.yield()
end

-- Discover IP address (UDP discovery). Must be called from inside a
-- coroutine: it yields while waiting for the discovery response, the
-- same pattern as receive(). The response arrives through the same
-- recv_start callback as RTP packets (see _handle_rtp), which routes
-- it here via state.discovery_waiter instead of the normal packet path
-- whenever a discovery request is outstanding.
function UDPClient:discover_ip()
    local state = self._state

    if not state.udp then
        return false, "UDP socket not initialized"
    end

    local co = coroutine.running()
    if not co then
        error("UDPClient:discover_ip must be called from within a coroutine")
    end

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

    local success, err = state.udp:send(discovery_packet, state.remote_ip, state.remote_port)
    if not success then
        return false, "Failed to send discovery packet: " .. tostring(err)
    end

    local timer = uv.new_timer()
    state.discovery_waiter = { co = co, timer = timer }

    timer:start(1000, 0, function()
        local waiter = state.discovery_waiter
        if not waiter or waiter.co ~= co then
            return
        end
        state.discovery_waiter = nil
        coroutine.resume(co, nil, "timeout")
    end)

    return coroutine.yield()
end

-- Resume the coroutine parked in discover_ip(), if any, with a parsed
-- ip/port. No-op if nothing is currently waiting.
function UDPClient:_resolve_discovery_waiter(ip, port)
    local state = self._state
    local waiter = state.discovery_waiter
    if not waiter then
        return
    end
    state.discovery_waiter = nil
    if waiter.timer then
        waiter.timer:stop()
    end
    coroutine.resume(waiter.co, ip, port)
end

-- Parse discovery response (raw byte string, 74 bytes)
-- Byte 1-4: header (type + length)
-- Byte 5-8: SSRC
-- Byte 9-72: null terminated IP address string
-- Byte 73-74: port (big endian)
function UDPClient:_parse_discovery_response(data) -- luacheck: ignore
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

    if state.receive_waiter then
        local waiter = state.receive_waiter
        state.receive_waiter = nil
        if waiter.timer then
            waiter.timer:stop()
        end
        coroutine.resume(waiter.co, nil, "closed")
    end

    if state.discovery_waiter then
        local waiter = state.discovery_waiter
        state.discovery_waiter = nil
        if waiter.timer then
            waiter.timer:stop()
        end
        coroutine.resume(waiter.co, nil, "closed")
    end

    if state.udp then
        state.udp:close()
        state.udp = nil
    end

    state.connected = false
    state.remote_ip = nil
    state.remote_port = nil
    state.ip = nil
    state.port = nil
    state.buffer = nil

    return true
end

local M = {
    UDPClient = UDPClient,
}

return M
