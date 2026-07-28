-- lib/voice/crypto/le_salsa20poly1305.lua
-- Pure Lua implementation of XSalsa20 stream cipher + Poly1305 MAC,
-- combined into a NaCl-compatible secretbox (crypto_secretbox_easy).
--
-- No ffi, no bit/bit32 library, no C extension. Every bitwise operation
-- (and, or, xor, rotl) is implemented with plain arithmetic on Lua
-- numbers, so this file runs unmodified on standard Lua 5.1, 5.2, 5.3,
-- and LuaJIT. This is the fallback used by voice.crypto when ffi or a
-- system libsodium install are not available (e.g. plain Lua 5.1, or
-- LuaJIT without libsodium installed, such as on Windows without a
-- bundled libsodium.dll).
--
-- Algorithms implemented directly from their public specifications:
--   Salsa20/XSalsa20: Daniel J. Bernstein, https://cr.yp.to/snuffle.html
--   Poly1305: Daniel J. Bernstein, https://cr.yp.to/mac.html
--   NaCl secretbox construction (XSalsa20 stream cipher, first 32 bytes
--   of keystream used as the one-time Poly1305 key, remaining keystream
--   XORed with plaintext): https://nacl.cr.yp.to/secretbox.html
--
-- This is not an audited, side-channel-resistant, constant-time
-- implementation. It exists to make discord.lua's voice encryption work
-- everywhere Lua runs, without requiring a compiler or a system package.
-- Prefer the ffi+libsodium path (see crypto.lua) when it is available;
-- this pure-Lua path exists as a portable fallback, not a replacement.

local floor = math.floor
local char = string.char
local byte = string.byte
local sub = string.sub

local MOD = 4294967296  -- 2^32

-- 32-bit unsigned add (mod 2^32)
local function add32(a, b)
    return (a + b) % MOD
end

-- 32-bit xor, implemented bit-by-bit via arithmetic (no bit library)
local function xor32(a, b)
    local result = 0
    local bitval = 1
    for _ = 1, 32 do
        local abit = a % 2
        local bbit = b % 2
        if abit ~= bbit then
            result = result + bitval
        end
        a = floor(a / 2)
        b = floor(b / 2)
        bitval = bitval * 2
    end
    return result
end

-- 32-bit left rotate by n bits
local function rotl32(x, n)
    x = x % MOD
    local left = (x * (2 ^ n)) % MOD
    local right = floor(x / (2 ^ (32 - n)))
    return left + right
end

-- Quarter-round: modifies (a, b, c, d) in place, returns new values
local function quarterround(y0, y1, y2, y3)
    y1 = xor32(y1, rotl32(add32(y0, y3), 7))
    y2 = xor32(y2, rotl32(add32(y1, y0), 9))
    y3 = xor32(y3, rotl32(add32(y2, y1), 13))
    y0 = xor32(y0, rotl32(add32(y3, y2), 18))
    return y0, y1, y2, y3
end

-- Read a little-endian 32-bit word from a byte string at 1-indexed offset
local function le_bytes_to_word(s, offset)
    local b1, b2, b3, b4 = byte(s, offset, offset + 3)
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

-- Write a 32-bit word as 4 little-endian bytes
local function word_to_le_bytes(w)
    w = w % MOD
    local b1 = w % 256
    w = floor(w / 256)
    local b2 = w % 256
    w = floor(w / 256)
    local b3 = w % 256
    w = floor(w / 256)
    local b4 = w % 256
    return char(b1, b2, b3, b4)
end

-- Salsa20 core hash function: 20 rounds (10 double-rounds) over 16 words.
-- input/output are arrays (tables) of 16 32-bit words.
local function salsa20_core(input)
    local x = {}
    for i = 1, 16 do
        x[i] = input[i]
    end

    for _ = 1, 10 do
        -- column round (indices are 1-indexed, +1 vs the usual 0-indexed spec)
        x[1], x[5], x[9], x[13] = quarterround(x[1], x[5], x[9], x[13])
        x[6], x[10], x[14], x[2] = quarterround(x[6], x[10], x[14], x[2])
        x[11], x[15], x[3], x[7] = quarterround(x[11], x[15], x[3], x[7])
        x[16], x[4], x[8], x[12] = quarterround(x[16], x[4], x[8], x[12])

        -- row round
        x[1], x[2], x[3], x[4] = quarterround(x[1], x[2], x[3], x[4])
        x[6], x[7], x[8], x[5] = quarterround(x[6], x[7], x[8], x[5])
        x[11], x[12], x[9], x[10] = quarterround(x[11], x[12], x[9], x[10])
        x[16], x[13], x[14], x[15] = quarterround(x[16], x[13], x[14], x[15])
    end

    local out = {}
    for i = 1, 16 do
        out[i] = add32(x[i], input[i])
    end
    return out
end

-- Build the 16-word Salsa20 input block from key (32 bytes), nonce
-- (8 bytes), and an 8-byte little-endian counter.
-- Constants are the ASCII bytes of "expand 32-byte k", split into four
-- little-endian words, as specified by Salsa20/NaCl.
local SIGMA = {
    0x61707865, -- "expa"
    0x3320646e, -- "nd 3"
    0x79622d32, -- "2-by"
    0x6b206574, -- "te k"
}

local function build_input(key, nonce8, counter8)
    local input = {}
    input[1] = SIGMA[1]
    input[2] = le_bytes_to_word(key, 1)
    input[3] = le_bytes_to_word(key, 5)
    input[4] = le_bytes_to_word(key, 9)
    input[5] = le_bytes_to_word(key, 13)
    input[6] = SIGMA[2]
    input[7] = le_bytes_to_word(nonce8, 1)
    input[8] = le_bytes_to_word(nonce8, 5)
    input[9] = le_bytes_to_word(counter8, 1)
    input[10] = le_bytes_to_word(counter8, 5)
    input[11] = SIGMA[3]
    input[12] = le_bytes_to_word(key, 17)
    input[13] = le_bytes_to_word(key, 21)
    input[14] = le_bytes_to_word(key, 25)
    input[15] = le_bytes_to_word(key, 29)
    input[16] = SIGMA[4]
    return input
end

-- HSalsa20: derives a 32-byte subkey from a 32-byte key and 16-byte nonce.
-- Used by XSalsa20 to extend the effective nonce to 24 bytes.
local function hsalsa20(key, nonce16)
    local input = {}
    input[1] = SIGMA[1]
    input[2] = le_bytes_to_word(key, 1)
    input[3] = le_bytes_to_word(key, 5)
    input[4] = le_bytes_to_word(key, 9)
    input[5] = le_bytes_to_word(key, 13)
    input[6] = SIGMA[2]
    input[7] = le_bytes_to_word(nonce16, 1)
    input[8] = le_bytes_to_word(nonce16, 5)
    input[9] = le_bytes_to_word(nonce16, 9)
    input[10] = le_bytes_to_word(nonce16, 13)
    input[11] = SIGMA[3]
    input[12] = le_bytes_to_word(key, 17)
    input[13] = le_bytes_to_word(key, 21)
    input[14] = le_bytes_to_word(key, 25)
    input[15] = le_bytes_to_word(key, 29)
    input[16] = SIGMA[4]

    -- HSalsa20 runs the same 20-round mixing but returns raw mixed words
    -- (no final feedforward addition), taking words at specific indices.
    local x = {}
    for i = 1, 16 do
        x[i] = input[i]
    end

    for _ = 1, 10 do
        x[1], x[5], x[9], x[13] = quarterround(x[1], x[5], x[9], x[13])
        x[6], x[10], x[14], x[2] = quarterround(x[6], x[10], x[14], x[2])
        x[11], x[15], x[3], x[7] = quarterround(x[11], x[15], x[3], x[7])
        x[16], x[4], x[8], x[12] = quarterround(x[16], x[4], x[8], x[12])

        x[1], x[2], x[3], x[4] = quarterround(x[1], x[2], x[3], x[4])
        x[6], x[7], x[8], x[5] = quarterround(x[6], x[7], x[8], x[5])
        x[11], x[12], x[9], x[10] = quarterround(x[11], x[12], x[9], x[10])
        x[16], x[13], x[14], x[15] = quarterround(x[16], x[13], x[14], x[15])
    end

    return word_to_le_bytes(x[1]) .. word_to_le_bytes(x[6])
        .. word_to_le_bytes(x[11]) .. word_to_le_bytes(x[16])
        .. word_to_le_bytes(x[7]) .. word_to_le_bytes(x[8])
        .. word_to_le_bytes(x[9]) .. word_to_le_bytes(x[10])
end

-- Generate `length` bytes of Salsa20 keystream for the given 32-byte key
-- and 8-byte nonce, starting at block counter 0.
local function salsa20_stream(key, nonce8, length)
    local blocks = {}
    local counter_lo = 0
    local counter_hi = 0
    local remaining = length

    while remaining > 0 do
        local counter8 = word_to_le_bytes(counter_lo) .. word_to_le_bytes(counter_hi)
        local input = build_input(key, nonce8, counter8)
        local out = salsa20_core(input)

        local block_bytes = {}
        for i = 1, 16 do
            block_bytes[i] = word_to_le_bytes(out[i])
        end
        blocks[#blocks + 1] = table.concat(block_bytes)

        counter_lo = counter_lo + 1
        if counter_lo >= MOD then
            counter_lo = 0
            counter_hi = counter_hi + 1
        end

        remaining = remaining - 64
    end

    local stream = table.concat(blocks)
    return sub(stream, 1, length)
end

-- XOR two equal-length byte strings
local function xor_bytes(a, b)
    local out = {}
    for i = 1, #a do
        out[i] = char(xor32(byte(a, i), byte(b, i)))
    end
    return table.concat(out)
end

-- XSalsa20: extends Salsa20 to a 24-byte nonce via HSalsa20 subkey
-- derivation, then runs plain Salsa20 with the derived subkey and the
-- remaining 8 nonce bytes.
local function xsalsa20_stream(key, nonce24, length)
    local nonce16 = sub(nonce24, 1, 16)
    local nonce8 = sub(nonce24, 17, 24)
    local subkey = hsalsa20(key, nonce16)
    return salsa20_stream(subkey, nonce8, length)
end

-- i hate everything about this but myabe i`ll figure it out later
local function xsalsa20_xor(key, nonce24, data)
    local stream = xsalsa20_stream(key, nonce24, #data)
    return xor_bytes(data, stream)
end

-- ===== Poly1305 =====
-- Poly1305 operates over a large integer modulus (2^130 - 5). Lua numbers
-- (IEEE754 doubles, on every target here: Lua 5.1/5.2/5.3/5.4 and
-- LuaJIT) carry 53 bits of exact integer precision. Schoolbook
-- multiplication of two big-number limbs must keep every intermediate
-- sum-of-products within that 53-bit budget, or the result silently
-- depends on floating point rounding order, which differs across Lua
-- versions/compilers (observed: identical Lua source produced off-by-one
-- limb values between Lua 5.1 and 5.3 when limbs were 26 bits wide,
-- because a single product neared 53 bits and summing several of them
-- overflowed the mantissa).
--
-- To stay safely inside the 53-bit budget, the accumulator and the
-- clamped key are split into ten 13-bit limbs (10 * 13 = 130 bits
-- exactly). Each product of two limbs is at most 26 bits, multiplying
-- by the reduction factor (5) adds under 3 bits, and summing up to ten
-- such terms adds under 4 more bits: a comfortable ~33 bits, far under
-- the 53-bit exact-integer ceiling of a double. This mirrors the
-- limb-splitting technique used by portable big-number implementations,
-- just with a conservative limb size chosen for Lua's numeric model
-- rather than for a 32-bit C `int`.

local LIMB_BASE = 8192 -- 2^13, i.e. 13-bit limbs
local NUM_LIMBS = 10   -- 10 * 13 = 130 bits

-- Split a byte string (little-endian, `nbytes` long) into `NUM_LIMBS`
-- limbs of `LIMB_BITS` bits each, via repeated base-256 long division.
local function bytes_to_limbs(s, nbytes)
    local digits = {}
    for i = 1, nbytes do
        digits[i] = byte(s, i)
    end
    local limbs = {}
    for _ = 1, NUM_LIMBS do
        local rem = 0
        for i = nbytes, 1, -1 do
            local cur = rem * 256 + digits[i]
            digits[i] = floor(cur / LIMB_BASE)
            rem = cur % LIMB_BASE
        end
        limbs[#limbs + 1] = rem
    end
    return limbs
end

-- Convert NUM_LIMBS limbs (13 bits each, little-endian) back into a
-- 16-byte little-endian string (only the low 128 bits are kept, which
-- is exactly what the Poly1305 tag needs).
local function limbs_to_bytes16(limbs)
    local digits = {}
    for i = 1, 17 do
        digits[i] = 0
    end
    for li = NUM_LIMBS, 1, -1 do
        local mulcarry = 0
        for i = 1, 17 do
            local cur = digits[i] * LIMB_BASE + mulcarry
            digits[i] = cur % 256
            mulcarry = floor(cur / 256)
        end
        local addcarry = limbs[li]
        local i = 1
        while addcarry > 0 do
            local cur = digits[i] + addcarry
            digits[i] = cur % 256
            addcarry = floor(cur / 256)
            i = i + 1
        end
    end
    local out = {}
    for i = 1, 16 do
        out[i] = char(digits[i])
    end
    return table.concat(out)
end

local function poly1305_mac(msg, key32)
    -- Clamp r (first 16 bytes of key) per the Poly1305 spec: clear
    -- specific bits so r's top nibble/pairs of bits are always zero.
    local r_raw = { byte(key32, 1, 16) }
    r_raw[4] = r_raw[4] % 16   -- byte index 3 (0-indexed) &= 0x0f
    r_raw[8] = r_raw[8] % 16   -- byte index 7 &= 0x0f
    r_raw[12] = r_raw[12] % 16 -- byte index 11 &= 0x0f
    r_raw[16] = r_raw[16] % 16 -- byte index 15 &= 0x0f
    r_raw[5] = r_raw[5] - (r_raw[5] % 4)   -- byte index 4 &= 0xfc
    r_raw[9] = r_raw[9] - (r_raw[9] % 4)   -- byte index 8 &= 0xfc
    r_raw[13] = r_raw[13] - (r_raw[13] % 4) -- byte index 12 &= 0xfc

    local r_bytes = {}
    for i = 1, 16 do
        r_bytes[i] = char(r_raw[i])
    end
    local r = bytes_to_limbs(table.concat(r_bytes), 16)

    -- Precompute r * 5 for each limb (used in the reduction step)
    local r5 = {}
    for i = 1, NUM_LIMBS do
        r5[i] = r[i] * 5
    end

    -- Accumulator, ten 13-bit limbs, starts at 0
    local h = {}
    for i = 1, NUM_LIMBS do
        h[i] = 0
    end

    local msg_len = #msg
    local pos = 1

    while pos <= msg_len do
        local chunk_len = 16
        if msg_len - pos + 1 < 16 then
            chunk_len = msg_len - pos + 1
        end
        local chunk = sub(msg, pos, pos + chunk_len - 1)

        -- Pad this block to 17 bytes: the message bytes, a trailing
        -- 0x01 byte, then zeros. This bakes in the "add 2^(8*len)" step
        -- from the spec (the 0x01 lands exactly at that bit position).
        local block_bytes = {}
        for i = 1, chunk_len do
            block_bytes[i] = char(byte(chunk, i))
        end
        block_bytes[chunk_len + 1] = char(1)
        for i = chunk_len + 2, 17 do
            block_bytes[i] = char(0)
        end
        local c = bytes_to_limbs(table.concat(block_bytes), 17)

        -- h += block (limb-wise; each limb is well under 2^13 + 2^13,
        -- carry gets folded in during the multiply-reduce carry chain
        -- below, so a plain add here is safe)
        for i = 1, NUM_LIMBS do
            h[i] = h[i] + c[i]
        end

        -- h = (h * r) mod (2^130 - 5), schoolbook multiply across the
        -- ten limbs. Products that land at or beyond limb position 10
        -- represent coefficients of 2^130 and above; since 2^130 = 5
        -- (mod 2^130 - 5), those contributions get multiplied by 5 and
        -- folded back into the low limbs instead of forming limbs 11+.
        local d = {}
        for i = 1, NUM_LIMBS do
            d[i] = 0
        end
        for i = 1, NUM_LIMBS do
            local hi = h[i]
            if hi ~= 0 then
                for j = 1, NUM_LIMBS do
                    local pos_limb = i + j - 1 -- 1-indexed target limb for x^(i-1) * x^(j-1)
                    if pos_limb <= NUM_LIMBS then
                        d[pos_limb] = d[pos_limb] + hi * r[j]
                    else
                        -- wraps past limb 10: fold back multiplied by 5
                        d[pos_limb - NUM_LIMBS] = d[pos_limb - NUM_LIMBS] + hi * r5[j]
                    end
                end
            end
        end

        -- carry propagation across all ten 13-bit limbs
        local carry = 0
        for i = 1, NUM_LIMBS do
            d[i] = d[i] + carry
            carry = floor(d[i] / LIMB_BASE)
            h[i] = d[i] % LIMB_BASE
        end
        -- final carry wraps past limb 10 representing 2^130, fold *5
        -- back into limb 1
        h[1] = h[1] + carry * 5
        carry = floor(h[1] / LIMB_BASE); h[1] = h[1] % LIMB_BASE; h[2] = h[2] + carry
        for i = 2, NUM_LIMBS - 1 do
            carry = floor(h[i] / LIMB_BASE); h[i] = h[i] % LIMB_BASE; h[i + 1] = h[i + 1] + carry
        end
        carry = floor(h[NUM_LIMBS] / LIMB_BASE); h[NUM_LIMBS] = h[NUM_LIMBS] % LIMB_BASE
        h[1] = h[1] + carry * 5
        carry = floor(h[1] / LIMB_BASE); h[1] = h[1] % LIMB_BASE; h[2] = h[2] + carry

        pos = pos + chunk_len
    end

    -- Fully normalize h to canonical limbs < 2^13 (the loop above may
    -- leave a small residual carry in the low limbs after the last
    -- block, since only h[1]/h[2] got a final pass).
    local carry = 0
    for i = 1, NUM_LIMBS - 1 do
        h[i] = h[i] + carry
        carry = floor(h[i] / LIMB_BASE); h[i] = h[i] % LIMB_BASE
        h[i + 1] = h[i + 1] + carry
    end
    carry = floor(h[NUM_LIMBS] / LIMB_BASE); h[NUM_LIMBS] = h[NUM_LIMBS] % LIMB_BASE
    h[1] = h[1] + carry * 5
    carry = floor(h[1] / LIMB_BASE); h[1] = h[1] % LIMB_BASE; h[2] = h[2] + carry
    for i = 2, NUM_LIMBS - 1 do
        carry = floor(h[i] / LIMB_BASE); h[i] = h[i] % LIMB_BASE
        h[i + 1] = h[i + 1] + carry
    end
    h[NUM_LIMBS] = h[NUM_LIMBS] % LIMB_BASE

    -- Final reduction: if h >= 2^130 - 5, subtract it (at most one
    -- subtraction is ever needed at this point). Test by computing
    -- g = h + 5 - 2^130 and checking whether it underflows.
    local g = {}
    local gc = 5
    for i = 1, NUM_LIMBS do
        g[i] = h[i] + gc
        gc = floor(g[i] / LIMB_BASE)
        g[i] = g[i] % LIMB_BASE
    end
    -- gc now holds the carry out of the top limb; since h < 2^131 and we
    -- added 5, gc is 1 exactly when h + 5 >= 2^130, i.e. h >= 2^130 - 5.
    if gc >= 1 then
        h = g
    end

    -- Convert the (now canonical, < 2^130 - 5 < 2^128 is not guaranteed,
    -- but only the low 128 bits matter per the spec) limbs to 16 bytes.
    local h_bytes = limbs_to_bytes16(h)

    -- s = last 16 bytes of the key, added to h mod 2^128
    local s_bytes = { byte(key32, 17, 32) }
    local h_digits = { byte(h_bytes, 1, 16) }
    local out_digits = {}
    local carry_add = 0
    for i = 1, 16 do
        local sum = h_digits[i] + s_bytes[i] + carry_add
        out_digits[i] = sum % 256
        carry_add = floor(sum / 256)
    end

    local out = {}
    for i = 1, 16 do
        out[i] = char(out_digits[i])
    end
    return table.concat(out)
end

-- ===== Public secretbox API (NaCl crypto_secretbox_easy compatible) =====

local KEY_SIZE = 32
local NONCE_SIZE = 24
local MACBYTES = 16

local M = {}

M.key_size = KEY_SIZE
M.nonce_size = NONCE_SIZE
M.macbytes = MACBYTES

-- Encrypt plaintext, returns ciphertext = mac (16 bytes) .. box
function M.encrypt(plaintext, nonce, key)
    -- First 32 bytes of XSalsa20 keystream: first 32 used as the
    -- one-time Poly1305 key, remaining keystream XORed with plaintext
    -- starting at that same stream position (NaCl secretbox convention:
    -- the first block's first 32 bytes are reserved, encryption starts
    -- at stream offset 32 within block 0, i.e. the plaintext is XORed
    -- against keystream bytes [32, 32+#plaintext)).
    local needed = 32 + #plaintext
    local stream = xsalsa20_stream(key, nonce, needed)
    local poly_key = sub(stream, 1, 32)
    local pad = sub(stream, 33, needed)

    local box = xor_bytes(plaintext, pad)
    local mac = poly1305_mac(box, poly_key)

    return mac .. box
end

-- Decrypt ciphertext (mac .. box), returns plaintext or nil, err
function M.decrypt(ciphertext, nonce, key)
    if #ciphertext < MACBYTES then
        return nil, "ciphertext too short"
    end

    local mac = sub(ciphertext, 1, MACBYTES)
    local box = sub(ciphertext, MACBYTES + 1)

    local needed = 32 + #box
    local stream = xsalsa20_stream(key, nonce, needed)
    local poly_key = sub(stream, 1, 32)
    local pad = sub(stream, 33, needed)

    local expected_mac = poly1305_mac(box, poly_key)

    if expected_mac ~= mac then
        return nil, "decryption failed, invalid mac or corrupted data"
    end

    return xor_bytes(box, pad)
end

-- Random nonce generation. Prefers libuv's uv_random (the same CSPRNG
-- source used by Node.js and every other libuv-based runtime: getrandom()
-- on Linux, BCryptGenRandom on Windows, arc4random on BSD/macOS), which
-- Luvit already links in and requires no extra dependency. Falls back to
-- a Lua-only generator only if uv_random is unavailable (e.g. an
-- unusually old libuv build predating 1.33.0).
--
-- The fallback is a best-effort CSPRNG-ish generator, not a substitute
-- for a real one: it mixes os.time(), os.clock(), and table-address
-- entropy (ASLR-influenced, via tostring on a fresh table) into Lua's
-- math.random. This is meaningfully weaker than getrandom()/arc4random
-- and is only reached when both libsodium and libuv's random are
-- absent; prefer fixing the environment (updating libuv) over relying
-- on this path for anything long-lived.
local uv_ok, uv = pcall(require, "core.luv_compat")
if not uv_ok then
    uv_ok, uv = pcall(require, "luv")
end
if not uv_ok then
    uv_ok, uv = pcall(require, "uv")
end
if not uv_ok then
    uv = nil
end

local fallback_seeded = false

local function fallback_random_bytes(n)
    if not fallback_seeded then
        local entropy = os.time() * 1000 + (os.clock() * 1000000) % 1000
        entropy = entropy + tonumber(tostring({}):match("0x(%x+)") or "0", 16) % 100000
        math.randomseed(entropy)
        fallback_seeded = true
    end

    local bytes = {}
    for i = 1, n do
        bytes[i] = char(math.random(0, 255))
    end
    return table.concat(bytes)
end

function M.random_nonce()
    if uv and uv.random then
        local ok, data = pcall(uv.random, NONCE_SIZE)
        if ok and data and #data == NONCE_SIZE then
            return data
        end
    end

    return fallback_random_bytes(NONCE_SIZE)
end

-- Exposed for testing / advanced use
M._internal = {
    salsa20_core = salsa20_core,
    salsa20_stream = salsa20_stream,
    xsalsa20_stream = xsalsa20_stream,
    xsalsa20_xor = xsalsa20_xor,
    hsalsa20 = hsalsa20,
    poly1305_mac = poly1305_mac,
    rotl32 = rotl32,
    xor32 = xor32,
    add32 = add32,
}

return M
