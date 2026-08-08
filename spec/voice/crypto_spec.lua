-- spec/voice/crypto_spec.lua
-- Tests for lib/voice/crypto.lua (XSalsa20-Poly1305 and AEAD
-- XChaCha20-Poly1305 using the libsodium FFI backend when available).

require("spec_helper")
package.path = "spec/voice/?.lua;" .. package.path

local crypto = require("./voice/crypto")

describe("Crypto", function()
    it("exposes size constants", function()
        assert.equals(32, crypto.key_size())
        assert.equals(24, crypto.nonce_size())
        assert.equals(16, crypto.macbytes())
    end)

    it("reports whether the libsodium backend is available", function()
        assert.is_boolean(crypto.available())
        assert.equals(crypto.available(), crypto.aead_available())

        local backend = crypto.backend()
        assert.is_true(backend == nil or backend == "libsodium")
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
