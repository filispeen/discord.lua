-- spec/voice/crypto_spec.lua
-- Tests for lib/voice/crypto.lua (XSalsa20-Poly1305, libsodium FFI or
-- pure-Lua fallback depending on the runtime)
--
-- Crypto.available() is now always true: when libsodium/ffi is not
-- available (plain Lua 5.1, or LuaJIT without libsodium installed), the
-- module falls back to a pure-Lua XSalsa20-Poly1305 implementation with
-- no external dependency. The round-trip and validation tests below run
-- unconditionally, exercising whichever backend Crypto.backend()
-- reports for the current environment. Backend-specific behavior (which
-- one is picked, and that both produce mutually-compatible ciphertext)
-- is covered separately below.

require("spec_helper")
package.path = "spec/voice/?.lua;" .. package.path

local crypto = require("./voice/crypto")
local pure_lua = require("./voice/le_salsa20poly1305")

describe("Crypto", function()
    it("exposes size constants", function()
        assert.equals(32, crypto.key_size())
        assert.equals(24, crypto.nonce_size())
        assert.equals(16, crypto.macbytes())
    end)

    it("is always available, backed by libsodium or the pure-Lua fallback", function()
        assert.is_true(crypto.available())
        local backend = crypto.backend()
        assert.is_true(backend == "libsodium" or backend == "pure_lua")
    end)

    it("round-trips plaintext through encrypt/decrypt", function()
        local key = string.rep("k", crypto.key_size())
        local nonce = string.rep("n", crypto.nonce_size())
        local plaintext = "the quick brown fox jumps over the lazy dog"

        local ciphertext, err = crypto.encrypt(plaintext, nonce, key)
        assert.is_nil(err)
        assert.is_string(ciphertext)
        assert.equals(#plaintext + crypto.macbytes(), #ciphertext)

        local decrypted, derr = crypto.decrypt(ciphertext, nonce, key)
        assert.is_nil(derr)
        assert.equals(plaintext, decrypted)
    end)

    it("rejects tampered ciphertext", function()
        local key = string.rep("k", crypto.key_size())
        local nonce = string.rep("n", crypto.nonce_size())

        local ciphertext = crypto.encrypt("payload data", nonce, key)
        local tampered = ciphertext:sub(1, -2) .. string.char((ciphertext:byte(-1) + 1) % 256)

        local decrypted, err = crypto.decrypt(tampered, nonce, key)
        assert.is_nil(decrypted)
        assert.is_string(err)
    end)

    it("rejects wrong key size", function()
        local nonce = string.rep("n", crypto.nonce_size())
        local ct, err = crypto.encrypt("data", nonce, "short_key")
        assert.is_nil(ct)
        assert.is_string(err)
    end)

    it("rejects wrong nonce size", function()
        local key = string.rep("k", crypto.key_size())
        local ct, err = crypto.encrypt("data", "short_nonce", key)
        assert.is_nil(ct)
        assert.is_string(err)
    end)

    it("random_nonce returns distinct, correctly-sized nonces", function()
        local n1 = crypto.random_nonce()
        local n2 = crypto.random_nonce()
        assert.equals(crypto.nonce_size(), #n1)
        assert.equals(crypto.nonce_size(), #n2)
        assert.is_not_equal(n1, n2)
    end)

    describe("pure-Lua backend", function()
        it("independently round-trips plaintext (used directly, bypassing libsodium)", function()
            local key = string.rep("k", pure_lua.key_size)
            local nonce = string.rep("n", pure_lua.nonce_size)
            local plaintext = "cross-backend compatibility check"

            local ciphertext, err = pure_lua.encrypt(plaintext, nonce, key)
            assert.is_nil(err)
            assert.is_string(ciphertext)

            local decrypted, derr = pure_lua.decrypt(ciphertext, nonce, key)
            assert.is_nil(derr)
            assert.equals(plaintext, decrypted)
        end)

        if crypto.backend() == "libsodium" then
            it("produces ciphertext byte-identical to the active libsodium backend", function()
                -- Only meaningful when libsodium is actually active here
                -- (e.g. under LuaJIT with libsodium installed): proves
                -- the pure-Lua implementation is wire-compatible with
                -- real libsodium, not just internally consistent.
                local key = string.rep("k", crypto.key_size())
                local nonce = string.rep("n", crypto.nonce_size())
                local plaintext = "wire compatibility between backends"

                local sodium_ct = crypto.encrypt(plaintext, nonce, key)
                local pure_ct = pure_lua.encrypt(plaintext, nonce, key)

                assert.equals(sodium_ct, pure_ct)
            end)
        else
            pending("libsodium cross-check (requires LuaJIT + libsodium, not active in this environment)")
        end
    end)

    describe("AEAD XChaCha20-Poly1305 (aead_xchacha20_poly1305_rtpsize)", function()
        it("exposes size constants", function()
            assert.equals(32, crypto.aead_key_size())
            assert.equals(24, crypto.aead_nonce_size())
            assert.equals(16, crypto.aead_macbytes())
        end)

        if crypto.aead_available() then
            it("round-trips plaintext through aead_encrypt/aead_decrypt", function()
                local key = string.rep("k", crypto.aead_key_size())
                local nonce = string.rep("n", crypto.aead_nonce_size())
                local aad = "unencrypted-rtp-header"
                local plaintext = "the quick brown fox jumps over the lazy dog"

                local ciphertext, err = crypto.aead_encrypt(plaintext, nonce, key, aad)
                assert.is_nil(err)
                assert.is_string(ciphertext)
                assert.equals(#plaintext + crypto.aead_macbytes(), #ciphertext)

                local decrypted, derr = crypto.aead_decrypt(ciphertext, nonce, key, aad)
                assert.is_nil(derr)
                assert.equals(plaintext, decrypted)
            end)

            it("round-trips empty plaintext", function()
                local key = string.rep("k", crypto.aead_key_size())
                local nonce = string.rep("n", crypto.aead_nonce_size())

                local ciphertext = crypto.aead_encrypt("", nonce, key, "")
                assert.equals(crypto.aead_macbytes(), #ciphertext)

                local decrypted = crypto.aead_decrypt(ciphertext, nonce, key, "")
                assert.equals("", decrypted)
            end)

            it("rejects tampered ciphertext", function()
                local key = string.rep("k", crypto.aead_key_size())
                local nonce = string.rep("n", crypto.aead_nonce_size())
                local ciphertext = crypto.aead_encrypt("payload", nonce, key, "aad")

                local tampered = ciphertext:sub(1, -2) .. string.char((ciphertext:byte(-1) + 1) % 256)
                local decrypted, err = crypto.aead_decrypt(tampered, nonce, key, "aad")

                assert.is_nil(decrypted)
                assert.is_not_nil(err)
            end)

            it("rejects mismatched additional authenticated data", function()
                local key = string.rep("k", crypto.aead_key_size())
                local nonce = string.rep("n", crypto.aead_nonce_size())
                local ciphertext = crypto.aead_encrypt("payload", nonce, key, "correct-aad")

                local decrypted, err = crypto.aead_decrypt(ciphertext, nonce, key, "wrong-aad")

                assert.is_nil(decrypted)
                assert.is_not_nil(err)
            end)

            it("rejects wrong key size", function()
                local nonce = string.rep("n", crypto.aead_nonce_size())
                local ciphertext, err = crypto.aead_encrypt("payload", nonce, "too_short", "")

                assert.is_nil(ciphertext)
                assert.matches("key size", err)
            end)

            it("rejects wrong nonce size", function()
                local key = string.rep("k", crypto.aead_key_size())
                local ciphertext, err = crypto.aead_encrypt("payload", "too_short", key, "")

                assert.is_nil(ciphertext)
                assert.matches("nonce size", err)
            end)
        else
            it("returns an error rather than encrypting when libsodium is unavailable", function()
                local key = string.rep("k", crypto.aead_key_size())
                local nonce = string.rep("n", crypto.aead_nonce_size())
                local ciphertext, err = crypto.aead_encrypt("payload", nonce, key, "")

                assert.is_nil(ciphertext)
                assert.matches("libsodium", err)
            end)

            pending("AEAD XChaCha20-Poly1305 round-trip (requires LuaJIT + libsodium, not active in this environment)")
        end
    end)
end)
