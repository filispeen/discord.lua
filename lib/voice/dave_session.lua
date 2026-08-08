-- lib/voice/dave_session.lua
-- DAVE (MLS-based E2EE) session orchestration: wraps a single libdave
-- DAVESessionHandle (see dave_ffi.lua) with the lifecycle operations the
-- voice gateway needs -- init/reinit, process incoming MLS proposals/
-- commit/welcome, execute a Discord-announced transition, and drive the
-- encryptor/decryptor for RTP frames. This mirrors pycord's
-- discord/voice/state.py (reinit_dave_session, execute_dave_transition,
-- recover_dave_from_invalid_commit) and the DAVESession-handling half of
-- discord/voice/gateway.py's received_message/received_binary_message,
-- translated from davey's Python object API to libdave's C handle API.
--
-- Public Contract:
--   DaveSession.new(user_id, channel_id) -> session or nil, err
--     Fails (returns nil, err) if dave_ffi.available() is false, i.e. no
--     libdave shared library was found. Callers (voice_gateway.lua) must
--     treat that as "DAVE unsupported", not a hard error: it means this
--     build cannot join DAVE-mandatory channels at all (see
--     CLOSE_DAVE_PROTOCOL_REQUIRED in enums.lua), but should not crash.
--   session:init(protocol_version) -- daveSessionInit, only valid once
--   session:reinit(protocol_version) -- re-creates the underlying MLS
--     group for a new protocol version, called on every session_description
--     and on dave_prepare_epoch epoch=1 (new group), matching
--     reinit_dave_session in pycord
--   session:reset() -- daveSessionReset, used when downgrading to
--     protocol_version 0 (DAVE turned off for this call)
--   session:get_serialized_key_package() -> bytes -- for MLS_KEY_PACKAGE
--   session:set_external_sender(bytes) -- for MLS_EXTERNAL_SENDER_PACKAGE
--   session:process_proposals(op_type, bytes) -> commit_welcome_bytes or nil
--     op_type: "append" or "revoke" (davey.ProposalsOperationType
--     equivalent, read from byte 0 of the MLS_PROPOSALS payload by the
--     caller). Returns the bytes to send back as MLS_COMMIT_WELCOME, or
--     nil if nothing needs to be sent.
--   session:process_commit(bytes) -> ok, err -- for MLS_COMMIT_TRANSITION.
--     ok is false (not a Lua error) on a rejected/ignored commit, mirroring
--     libdave's DAVECommitResultHandle IsFailed/IsIgnored rather than an
--     exception (pycord's davey raises here instead; libdave's C API
--     returns a result handle, which this wraps back into ok, err since
--     dave_session.lua's own callers already expect ok, err everywhere
--     else in this codebase).
--   session:process_welcome(bytes) -> ok, err -- for MLS_WELCOME, same
--     ok, err contract as process_commit
--   session:set_passthrough_mode(enabled) -- forwards to both the
--     encryptor and decryptor; used during downgrade/recovery
--   session:encrypt_opus(ssrc, plaintext) -> ciphertext or nil, err
--   session:decrypt_opus(ciphertext) -> plaintext or nil, err
--   session:destroy() -- frees the underlying FFI handles; must be
--     called exactly once when the voice connection is fully torn down
--     (not on every reconnect/reinit), same rule as any other libdave
--     handle in this file

local dave_ffi = require("./dave_ffi")

local DaveSession = {}
DaveSession.__index = DaveSession

local ffi = nil
do
    local ok, mod = pcall(require, "ffi")
    if ok then
        ffi = mod
    end
end

-- MLS proposals operation type byte values, matching davey.ProposalsOperationType
-- (pycord discord/voice/gateway.py: op_type = msg[3]; 0 = append, 1 = revoke).
local PROPOSALS_OP_APPEND = 0
local PROPOSALS_OP_REVOKE = 1

local function ffi_string_free(ptr_ptr, len_ptr)
    if ptr_ptr[0] == nil then
        return nil
    end

    local length = tonumber(len_ptr[0])
    if length == 0 then
        dave_ffi.lib.daveFree(ptr_ptr[0])
        return ""
    end

    local str = ffi.string(ptr_ptr[0], length)
    dave_ffi.lib.daveFree(ptr_ptr[0])
    return str
end

function DaveSession.new(user_id, channel_id)
    if not dave_ffi.available() then
        return nil, "libdave not available"
    end

    if not user_id or not channel_id then
        return nil, "user_id and channel_id are required"
    end

    local self = setmetatable({}, DaveSession)
    self.lib = dave_ffi.lib
    self.user_id = tostring(user_id)
    self.channel_id = tostring(channel_id)
    self.protocol_version = 0
    self.handle = nil
    self.encryptor = nil
    self.decryptor = nil
    self.key_ratchets = {}

    local create_ok, handle = pcall(function()
        return self.lib.daveSessionCreate(nil, nil, nil, nil)
    end)

    if not create_ok or handle == nil then
        return nil, "daveSessionCreate failed"
    end

    self.handle = handle

    local enc_ok, encryptor = pcall(function()
        return self.lib.daveEncryptorCreate()
    end)
    local dec_ok, decryptor = pcall(function()
        return self.lib.daveDecryptorCreate()
    end)

    if not enc_ok or encryptor == nil or not dec_ok or decryptor == nil then
        self.lib.daveSessionDestroy(self.handle)
        return nil, "daveEncryptorCreate/daveDecryptorCreate failed"
    end

    self.encryptor = encryptor
    self.decryptor = decryptor

    return self
end

-- Discord snowflakes are unsigned 64-bit integers, but arrive here as
-- decimal strings (self.channel_id is tostring()'d in DaveSession.new).
-- tonumber(channel_id) would round-trip through a Lua double first,
-- which only has 53 bits of integer precision -- silently corrupting
-- any snowflake above 2^53 (~9.007e15), which real channel/guild IDs
-- routinely exceed. This parses the decimal string directly into a
-- uint64_t via LuaJIT's 64-bit integer arithmetic instead, so the group
-- ID libdave uses for MLS group identity actually matches the channel
-- ID Discord sent, digit for digit.
local function group_id_from_channel_id(channel_id)
    local result = ffi.new("uint64_t", 0)
    for i = 1, #channel_id do
        local digit = channel_id:byte(i) - 48
        if digit < 0 or digit > 9 then
            return ffi.new("uint64_t", 0)
        end
        result = result * 10 + digit
    end
    return result
end

function DaveSession:init(protocol_version)
    self.protocol_version = protocol_version
    self.lib.daveSessionInit(self.handle, protocol_version,
        group_id_from_channel_id(self.channel_id), self.user_id)
end

-- Re-creates the MLS group for a (possibly new) protocol_version, mirrors
-- pycord's reinit_dave_session: called whenever we get a fresh
-- session_description with dave_protocol_version > 0, or a
-- dave_prepare_epoch with epoch == 1 (brand new group).
function DaveSession:reinit(protocol_version)
    self.protocol_version = protocol_version
    self.lib.daveSessionInit(self.handle, protocol_version,
        group_id_from_channel_id(self.channel_id), self.user_id)
end

function DaveSession:reset()
    self.lib.daveSessionReset(self.handle)
    self.protocol_version = 0
end

function DaveSession:get_serialized_key_package()
    local out_ptr = ffi.new("uint8_t*[1]")
    local out_len = ffi.new("size_t[1]")

    self.lib.daveSessionGetMarshalledKeyPackage(self.handle, out_ptr, out_len)

    return ffi_string_free(out_ptr, out_len)
end

function DaveSession:set_external_sender(bytes)
    local data = ffi.cast("const uint8_t*", bytes)
    self.lib.daveSessionSetExternalSender(self.handle, data, #bytes)
end

-- op_type: "append" or "revoke". recognized_user_ids is an optional list
-- of user id strings (davey passes session.get_user_ids() here in
-- pycord); when omitted, an empty list is sent, matching the "we don't
-- track a roster yet" state this library starts in.
function DaveSession:process_proposals(op_type, bytes, recognized_user_ids)
    recognized_user_ids = recognized_user_ids or {}

    local op_byte = op_type == "revoke" and PROPOSALS_OP_REVOKE or PROPOSALS_OP_APPEND

    local ids_array = ffi.new("const char*[?]", #recognized_user_ids + 1)
    for i, id in ipairs(recognized_user_ids) do
        ids_array[i - 1] = id
    end

    local data = ffi.cast("const uint8_t*", bytes)
    local out_ptr = ffi.new("uint8_t*[1]")
    local out_len = ffi.new("size_t[1]")

    -- op_byte is not part of libdave's C signature (unlike davey's
    -- ProposalsOperationType enum arg); the C API only takes the raw
    -- proposal bytes. op_type is kept as a parameter here anyway since
    -- callers (voice_gateway.lua) already have it available from
    -- msg[3] and it documents intent, even though it is presently
    -- unused by the libdave call itself.
    local _ = op_byte

    self.lib.daveSessionProcessProposals(self.handle, data, #bytes,
        ids_array, #recognized_user_ids, out_ptr, out_len)

    return ffi_string_free(out_ptr, out_len)
end

-- Returns ok, err instead of raising, since libdave's C API reports
-- commit failures via DAVECommitResultHandle:IsFailed/IsIgnored rather
-- than an exception (pycord's davey.DaveSession.process_commit raises
-- python-side, which state.py catches with a bare except).
function DaveSession:process_commit(bytes)
    local data = ffi.cast("const uint8_t*", bytes)

    local commit_ok, result = pcall(function()
        return self.lib.daveSessionProcessCommit(self.handle, data, #bytes)
    end)

    if not commit_ok or result == nil then
        return false, "daveSessionProcessCommit failed"
    end

    local failed = self.lib.daveCommitResultIsFailed(result)
    local ignored = self.lib.daveCommitResultIsIgnored(result)
    self.lib.daveCommitResultDestroy(result)

    if failed then
        return false, "MLS commit failed"
    end

    if ignored then
        return false, "MLS commit ignored"
    end

    return true
end

function DaveSession:process_welcome(bytes, recognized_user_ids)
    recognized_user_ids = recognized_user_ids or {}

    local ids_array = ffi.new("const char*[?]", #recognized_user_ids + 1)
    for i, id in ipairs(recognized_user_ids) do
        ids_array[i - 1] = id
    end

    local data = ffi.cast("const uint8_t*", bytes)

    local welcome_ok, result = pcall(function()
        return self.lib.daveSessionProcessWelcome(self.handle, data, #bytes,
            ids_array, #recognized_user_ids)
    end)

    if not welcome_ok or result == nil then
        return false, "daveSessionProcessWelcome failed"
    end

    self.lib.daveWelcomeResultDestroy(result)
    return true
end

-- Refreshes this session's own key ratchet on the encryptor/decryptor
-- after a successful process_commit/process_welcome, so subsequent
-- encrypt_opus/decrypt_opus calls use the new epoch's keys. Not part of
-- pycord's flow directly (davey handles this internally), but required
-- here since libdave's C API exposes key ratchets as explicit handles
-- the caller must fetch and wire up itself.
function DaveSession:refresh_key_ratchet(user_id)
    user_id = user_id or self.user_id

    local old = self.key_ratchets[user_id]

    local ratchet_ok, ratchet = pcall(function()
        return self.lib.daveSessionGetKeyRatchet(self.handle, tostring(user_id))
    end)

    if not ratchet_ok or ratchet == nil then
        return false, "daveSessionGetKeyRatchet failed"
    end

    self.key_ratchets[user_id] = ratchet

    if user_id == self.user_id then
        self.lib.daveEncryptorSetKeyRatchet(self.encryptor, ratchet)
    end
    self.lib.daveDecryptorTransitionToKeyRatchet(self.decryptor, ratchet)

    if old then
        self.lib.daveKeyRatchetDestroy(old)
    end

    return true
end

function DaveSession:set_passthrough_mode(enabled)
    self.lib.daveEncryptorSetPassthroughMode(self.encryptor, enabled)
    self.lib.daveDecryptorTransitionToPassthroughMode(self.decryptor, enabled)
end

function DaveSession:assign_ssrc_to_opus(ssrc)
    self.lib.daveEncryptorAssignSsrcToCodec(self.encryptor, ssrc, self.lib.DAVE_CODEC_OPUS or 1)
end

function DaveSession:ready()
    return self.lib.daveEncryptorHasKeyRatchet(self.encryptor) == true
end

function DaveSession:encrypt_opus(ssrc, plaintext)
    local max_size = self.lib.daveEncryptorGetMaxCiphertextByteSize(
        self.encryptor, 0, #plaintext)  -- DAVE_MEDIA_TYPE_AUDIO = 0

    local out_buf = ffi.new("uint8_t[?]", max_size)
    local written = ffi.new("size_t[1]")
    local frame = ffi.cast("const uint8_t*", plaintext)

    local result = self.lib.daveEncryptorEncrypt(self.encryptor, 0, ssrc,
        frame, #plaintext, out_buf, max_size, written)

    if result ~= 0 then  -- DAVE_ENCRYPTOR_RESULT_CODE_SUCCESS = 0
        return nil, "dave encrypt failed, result code " .. tostring(tonumber(result))
    end

    return ffi.string(out_buf, tonumber(written[0]))
end

function DaveSession:decrypt_opus(ciphertext)
    local max_size = self.lib.daveDecryptorGetMaxPlaintextByteSize(
        self.decryptor, 0, #ciphertext)  -- DAVE_MEDIA_TYPE_AUDIO = 0

    local out_buf = ffi.new("uint8_t[?]", max_size)
    local written = ffi.new("size_t[1]")
    local frame = ffi.cast("const uint8_t*", ciphertext)

    local result = self.lib.daveDecryptorDecrypt(self.decryptor, 0,
        frame, #ciphertext, out_buf, max_size, written)

    if result ~= 0 then  -- DAVE_DECRYPTOR_RESULT_CODE_SUCCESS = 0
        return nil, "dave decrypt failed, result code " .. tostring(tonumber(result))
    end

    return ffi.string(out_buf, tonumber(written[0]))
end

function DaveSession:destroy()
    for _, ratchet in pairs(self.key_ratchets) do
        self.lib.daveKeyRatchetDestroy(ratchet)
    end
    self.key_ratchets = {}

    if self.encryptor then
        self.lib.daveEncryptorDestroy(self.encryptor)
        self.encryptor = nil
    end

    if self.decryptor then
        self.lib.daveDecryptorDestroy(self.decryptor)
        self.decryptor = nil
    end

    if self.handle then
        self.lib.daveSessionDestroy(self.handle)
        self.handle = nil
    end
end

return DaveSession
