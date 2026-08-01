-- lib/voice/crypto.lua
-- XSalsa20-Poly1305 encryption for Discord voice payloads.
--
-- Prefers libsodium via FFI (LuaJIT + libsodium installed) since it is
-- an audited, constant-time, native implementation. When that is not
-- available, falls back to a pure-Lua XSalsa20-
-- Poly1305 implementation (le_salsa20poly1305.lua) that has no
-- external dependency and runs unmodified on any Lua 5.1+. This means
-- voice encryption works everywhere discord.lua runs, not only on
-- Linux with a system libsodium package installed.
--
-- Public Contract:
--   Crypto.available() - true if either backend (libsodium or the
--     pure-Lua fallback) is ready. In practice this is always true now,
--     since the pure-Lua backend has no external requirements; kept for
--     API compatibility and to signal which backend is actually active
--     via Crypto.backend().
--   Crypto.backend() - "libsodium" or "pure_lua", whichever is active.
--   Crypto.key_size() - required secret key length in bytes (32)
--   Crypto.nonce_size() - required nonce length in bytes (24)
--   Crypto.macbytes() - Poly1305 MAC length in bytes (16)
--   Crypto.encrypt(plaintext, nonce, key) - returns ciphertext string or nil, err
--   Crypto.decrypt(ciphertext, nonce, key) - returns plaintext string or nil, err
--   Crypto.random_nonce() - returns nonce_size() random bytes. Uses
--     libsodium's CSPRNG when that backend is active, otherwise libuv's
--     uv_random (getrandom()/BCryptGenRandom/arc4random depending on
--     platform) via the pure-Lua backend. Do not use math.random
--     directly for nonces; nonce reuse breaks XSalsa20-Poly1305's
--     confidentiality guarantees.
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

local native_lib = require("./native_lib")

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

    -- Prefer the dll bundled in lib/dlls/ (see native_lib.lua) on
    -- Windows, since a bare ffi.load("sodium") only checks the OS's
    -- normal library search path and won't find it there on its own.
    -- Falls back to the bare name so a system-installed libsodium (the
    -- expected setup on Linux/macOS) still works.
    local bundled_path = native_lib.resolve("libsodium")

    local success = pcall(function()
        if bundled_path then
            sodium_lib = ffi.load(bundled_path)
        else
            sodium_lib = ffi.load("sodium")
        end
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
            void randombytes_buf(void *const buf, const size_t size);
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

-- Pure-Lua fallback, used whenever the libsodium FFI backend above did
-- not come up. Loaded lazily/unconditionally here since it is cheap
-- (no C calls, no external state) and always available.
local pure_lua = require("./le_salsa20poly1305")

local Crypto = {}

function Crypto.available()
    return sodium_ready or pure_lua ~= nil
end

function Crypto.backend()
    if sodium_ready then
        return "libsodium"
    end
    return "pure_lua"
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
    if #nonce ~= NONCE_SIZE then
        return nil, "invalid nonce size, expected " .. NONCE_SIZE .. " bytes"
    end

    if #key ~= KEY_SIZE then
        return nil, "invalid key size, expected " .. KEY_SIZE .. " bytes"
    end

    if not sodium_ready then
        return pure_lua.encrypt(plaintext, nonce, key)
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
    if #nonce ~= NONCE_SIZE then
        return nil, "invalid nonce size, expected " .. NONCE_SIZE .. " bytes"
    end

    if #key ~= KEY_SIZE then
        return nil, "invalid key size, expected " .. KEY_SIZE .. " bytes"
    end

    if #ciphertext < MACBYTES then
        return nil, "ciphertext too short"
    end

    if not sodium_ready then
        return pure_lua.decrypt(ciphertext, nonce, key)
    end

    local clen = #ciphertext
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

-- Returns nonce_size() random bytes: via libsodium's randombytes_buf
-- when that backend is active, otherwise via the pure-Lua backend's
-- random_nonce (libuv's uv_random, with a weaker Lua-only fallback if
-- even that is unavailable).
function Crypto.random_nonce()
    if not sodium_ready then
        return pure_lua.random_nonce()
    end

    local buf = ffi.new("unsigned char[?]", NONCE_SIZE)
    sodium_lib.randombytes_buf(buf, NONCE_SIZE)
    return ffi.string(buf, NONCE_SIZE)
end

return Crypto
