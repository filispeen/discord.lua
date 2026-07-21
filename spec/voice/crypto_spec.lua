-- spec/voice/crypto_spec.lua
-- Tests for lib/voice/crypto.lua (XSalsa20-Poly1305 via libsodium FFI)
--
-- Note: this environment's busted runs under plain Lua 5.1, not LuaJIT,
-- so ffi is unavailable here and Crypto.available() is expected to be
-- false. The graceful-degradation path is tested directly. The real
-- encrypt/decrypt round-trip is skipped (not faked) unless run under
-- LuaJIT with libsodium installed; it does not prove wire compatibility
-- with Discord's actual voice protocol, only that libsodium's box
-- round-trips through this module's FFI bindings correctly.

package.path = "lib/?.lua;lib/?/?.lua;spec/voice/?.lua;" .. package.path

local crypto = require("voice.crypto")

describe("Crypto", function()
    it("exposes size constants", function()
        assert.equals(32, crypto.key_size())
        assert.equals(24, crypto.nonce_size())
        assert.equals(16, crypto.macbytes())
    end)

    if not crypto.available() then
        it("degrades gracefully without ffi/libsodium", function()
            assert.is_false(crypto.available())

            local key = string.rep("k", crypto.key_size())
            local nonce = string.rep("n", crypto.nonce_size())

            local ct, err = crypto.encrypt("hello", nonce, key)
            assert.is_nil(ct)
            assert.is_string(err)

            local pt, derr = crypto.decrypt("whatever", nonce, key)
            assert.is_nil(pt)
            assert.is_string(derr)
        end)

        pending("encrypt/decrypt round-trip (requires LuaJIT + libsodium, not run under plain Lua)")
    else
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
    end
end)
