-- lib/voice/crypto.lua
-- XSalsa20-Poly1305 encryption for Discord voice payloads, via libsodium FFI
--
-- Public Contract:
--   Crypto.available() - true if ffi and libsodium loaded successfully
--   Crypto.key_size() - required secret key length in bytes (32)
--   Crypto.nonce_size() - required nonce length in bytes (24)
--   Crypto.macbytes() - Poly1305 MAC length in bytes (16)
--   Crypto.encrypt(plaintext, nonce, key) - returns ciphertext string or nil, err
--   Crypto.decrypt(ciphertext, nonce, key) - returns plaintext string or nil, err
--
-- All strings are treated as raw byte strings (Lua strings), not byte-index
-- tables. nonce must be exactly nonce_size() bytes, key exactly key_size()
-- bytes. Discord's xsalsa20_poly1305_suffix mode appends the 24-byte nonce
-- to the end of the RTP packet; xsalsa20_poly1305_lite/xsalsa20_poly1305
-- use different nonce placement, but nonce construction is the caller's
-- responsibility, not this module's.

local ffi_ok, ffi = pcall(require, "ffi")
if not ffi_ok then
    ffi = nil
end

local KEY_SIZE = 32
local NONCE_SIZE = 24
local MACBYTES = 16

local sodium_lib = nil
local sodium_ready = false

local function load_sodium()
    if not ffi_ok then
        return
    end

    if sodium_lib then
        return
    end

    local success = pcall(function()
        sodium_lib = ffi.load("sodium")
    end)

    if not success or not sodium_lib then
        sodium_lib = nil
        return
    end

    local decl_ok = pcall(function()
        ffi.cdef([[
            int sodium_init(void);
            int crypto_secretbox_easy(unsigned char *c, const unsigned char *m,
                unsigned long long mlen, const unsigned char *n, const unsigned char *k);
            int crypto_secretbox_open_easy(unsigned char *m, const unsigned char *c,
                unsigned long long clen, const unsigned char *n, const unsigned char *k);
        ]])
    end)

    if not decl_ok then
        sodium_lib = nil
        return
    end

    local init_ok = pcall(function()
        sodium_lib.sodium_init()
    end)

    if not init_ok then
        sodium_lib = nil
        return
    end

    sodium_ready = true
end

load_sodium()

local Crypto = {}

function Crypto.available()
    return sodium_ready
end

function Crypto.key_size()
    return KEY_SIZE
end

function Crypto.nonce_size()
    return NONCE_SIZE
end

function Crypto.macbytes()
    return MACBYTES
end

-- Encrypt plaintext with XSalsa20-Poly1305, returns ciphertext (mac || box)
function Crypto.encrypt(plaintext, nonce, key)
    if not sodium_ready then
        return nil, "libsodium not available"
    end

    if #nonce ~= NONCE_SIZE then
        return nil, "invalid nonce size, expected " .. NONCE_SIZE .. " bytes"
    end

    if #key ~= KEY_SIZE then
        return nil, "invalid key size, expected " .. KEY_SIZE .. " bytes"
    end

    local mlen = #plaintext
    local clen = mlen + MACBYTES
    local c = ffi.new("unsigned char[?]", clen)
    local m = ffi.cast("const unsigned char*", plaintext)
    local n = ffi.cast("const unsigned char*", nonce)
    local k = ffi.cast("const unsigned char*", key)

    local status = sodium_lib.crypto_secretbox_easy(c, m, mlen, n, k)
    if status ~= 0 then
        return nil, "crypto_secretbox_easy failed"
    end

    return ffi.string(c, clen)
end

-- Decrypt ciphertext (mac || box) with XSalsa20-Poly1305, returns plaintext
function Crypto.decrypt(ciphertext, nonce, key)
    if not sodium_ready then
        return nil, "libsodium not available"
    end

    if #nonce ~= NONCE_SIZE then
        return nil, "invalid nonce size, expected " .. NONCE_SIZE .. " bytes"
    end

    if #key ~= KEY_SIZE then
        return nil, "invalid key size, expected " .. KEY_SIZE .. " bytes"
    end

    local clen = #ciphertext
    if clen < MACBYTES then
        return nil, "ciphertext too short"
    end

    local mlen = clen - MACBYTES
    local m = ffi.new("unsigned char[?]", mlen)
    local c = ffi.cast("const unsigned char*", ciphertext)
    local n = ffi.cast("const unsigned char*", nonce)
    local k = ffi.cast("const unsigned char*", key)

    local status = sodium_lib.crypto_secretbox_open_easy(m, c, clen, n, k)
    if status ~= 0 then
        return nil, "decryption failed, invalid mac or corrupted data"
    end

    return ffi.string(m, mlen)
end

return Crypto
