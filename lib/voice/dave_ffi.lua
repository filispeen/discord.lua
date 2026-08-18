-- lib/voice/dave_ffi.lua
-- LuaJIT FFI binding to libdave's C API (discord/libdave, cpp/includes/dave/dave.h),
-- Discord's own DAVE (MLS-based E2EE) protocol library. This module only
-- declares the cdef and loads the shared library; the DAVE protocol state
-- machine (opcode handling, session lifecycle, transitions) lives in
-- lib/voice/dave_session.lua and lib/voice/voice_gateway.lua, mirroring how
-- pycord's discord/voice/utils/dependencies.py (HAS_DAVEY) only wraps its
-- davey Python binding without any protocol logic of its own.
--
-- Public Contract:
--   dave_ffi.available() -> boolean
--     true if FFI is present (LuaJIT only, no plain Lua 5.1 support here)
--     and libdave.so/.dll was found and loaded successfully. All other
--     functions in this module return nil, err when this is false; callers
--     (dave_session.lua) must check this before touching the C handle,
--     the same way crypto.lua checks sodium_ready before using sodium_lib.
--   dave_ffi.lib
--     the raw ffi.C-style loaded library table (ffi.load result), only
--     valid when available() is true. Exposed for dave_session.lua to
--     call daveSessionCreate/daveEncryptorEncrypt/etc directly rather than
--     wrapping every single one of libdave's ~40 exported functions here.
--   dave_ffi.max_supported_protocol_version() -> integer or nil, err
--     wraps daveMaxSupportedProtocolVersion(), used for the
--     max_dave_protocol_version field in IDENTIFY.
--
-- Build requirement: lib/dlls/libdave-x64.dll (Windows) and
-- lib/dlls/libdave.so (Linux) are bundled prebuilt binaries copied from
-- discord/libdave's official v1.1.1 GitHub release assets
-- (libdave-Windows-X64-boringssl.zip, libdave-Linux-X64-boringssl.zip),
-- not built from source in this repo. If those releases are ever
-- unavailable, a shared library can still be built manually from
-- github.com/discord/libdave (cpp/, ) and dropped in the
-- same place. Until libdave.{so,dll} exists at all, available() returns
-- false and voice connections stay limited to non-DAVE channels (which
-- no longer exist as of the 2026 DAVE enforcement rollout, see
-- CLOSE_DAVE_PROTOCOL_REQUIRED in enums.lua) -- so DAVE support is a hard
-- prerequisite for any live voice testing, not an optional upgrade.
-- No macOS binary is bundled; ffi.load falls back to a bare "dave" name
-- there, which requires a manually installed/built libdave.

local ffi_ok, ffi = pcall(require, "ffi")
if not ffi_ok then
    ffi = nil
end

local native_lib = require("./native_lib")

local dave_lib = nil
local dave_ready = false
local dave_log_sink = nil

local CDEF = [[
typedef struct DAVESessionHandle_s* DAVESessionHandle;
typedef struct DAVECommitResultHandle_s* DAVECommitResultHandle;
typedef struct DAVEWelcomeResultHandle_s* DAVEWelcomeResultHandle;
typedef struct DAVEKeyRatchetHandle_s* DAVEKeyRatchetHandle;
typedef struct DAVEEncryptorHandle_s* DAVEEncryptorHandle;
typedef struct DAVEDecryptorHandle_s* DAVEDecryptorHandle;

typedef enum {
    DAVE_CODEC_UNKNOWN = 0,
    DAVE_CODEC_OPUS = 1,
    DAVE_CODEC_VP8 = 2,
    DAVE_CODEC_VP9 = 3,
    DAVE_CODEC_H264 = 4,
    DAVE_CODEC_H265 = 5,
    DAVE_CODEC_AV1 = 6
} DAVECodec;

typedef enum {
    DAVE_MEDIA_TYPE_AUDIO = 0,
    DAVE_MEDIA_TYPE_VIDEO = 1
} DAVEMediaType;

typedef enum {
    DAVE_ENCRYPTOR_RESULT_CODE_SUCCESS = 0,
    DAVE_ENCRYPTOR_RESULT_CODE_ENCRYPTION_FAILURE = 1,
    DAVE_ENCRYPTOR_RESULT_CODE_MISSING_KEY_RATCHET = 2,
    DAVE_ENCRYPTOR_RESULT_CODE_MISSING_CRYPTOR = 3,
    DAVE_ENCRYPTOR_RESULT_CODE_TOO_MANY_ATTEMPTS = 4
} DAVEEncryptorResultCode;

typedef enum {
    DAVE_DECRYPTOR_RESULT_CODE_SUCCESS = 0,
    DAVE_DECRYPTOR_RESULT_CODE_DECRYPTION_FAILURE = 1,
    DAVE_DECRYPTOR_RESULT_CODE_MISSING_KEY_RATCHET = 2,
    DAVE_DECRYPTOR_RESULT_CODE_INVALID_NONCE = 3,
    DAVE_DECRYPTOR_RESULT_CODE_MISSING_CRYPTOR = 4
} DAVEDecryptorResultCode;

typedef enum {
    DAVE_LOGGING_SEVERITY_VERBOSE = 0,
    DAVE_LOGGING_SEVERITY_INFO = 1,
    DAVE_LOGGING_SEVERITY_WARNING = 2,
    DAVE_LOGGING_SEVERITY_ERROR = 3,
    DAVE_LOGGING_SEVERITY_NONE = 4
} DAVELoggingSeverity;

typedef void (*DAVEMLSFailureCallback)(const char* source, const char* reason, void* userData);
typedef void (*DAVEPairwiseFingerprintCallback)(const uint8_t* fingerprint, size_t length, void* userData);
typedef void (*DAVEEncryptorProtocolVersionChangedCallback)(void* userData);
typedef void (*DAVELogSinkCallback)(DAVELoggingSeverity severity, const char* file, int line, const char* message);

typedef struct DAVEEncryptorStats {
    uint64_t passthroughCount;
    uint64_t encryptSuccessCount;
    uint64_t encryptFailureCount;
    uint64_t encryptDuration;
    uint64_t encryptAttempts;
    uint64_t encryptMaxAttempts;
    uint64_t encryptMissingKeyCount;
} DAVEEncryptorStats;

typedef struct DAVEDecryptorStats {
    uint64_t passthroughCount;
    uint64_t decryptSuccessCount;
    uint64_t decryptFailureCount;
    uint64_t decryptDuration;
    uint64_t decryptAttempts;
    uint64_t decryptMissingKeyCount;
    uint64_t decryptInvalidNonceCount;
} DAVEDecryptorStats;

uint16_t daveMaxSupportedProtocolVersion(void);

void daveFree(void* ptr);

DAVESessionHandle daveSessionCreate(void* context, const char* authSessionId,
    DAVEMLSFailureCallback callback, void* userData);
void daveSessionDestroy(DAVESessionHandle session);
void daveSessionInit(DAVESessionHandle session, uint16_t version, uint64_t groupId,
    const char* selfUserId);
void daveSessionReset(DAVESessionHandle session);
void daveSessionSetProtocolVersion(DAVESessionHandle session, uint16_t version);
uint16_t daveSessionGetProtocolVersion(DAVESessionHandle session);
void daveSessionGetLastEpochAuthenticator(DAVESessionHandle session,
    uint8_t** authenticator, size_t* length);
void daveSessionSetExternalSender(DAVESessionHandle session,
    const uint8_t* externalSender, size_t length);
void daveSessionProcessProposals(DAVESessionHandle session, const uint8_t* proposals,
    size_t length, const char** recognizedUserIds, size_t recognizedUserIdsLength,
    uint8_t** commitWelcomeBytes, size_t* commitWelcomeBytesLength);
DAVECommitResultHandle daveSessionProcessCommit(DAVESessionHandle session,
    const uint8_t* commit, size_t length);
DAVEWelcomeResultHandle daveSessionProcessWelcome(DAVESessionHandle session,
    const uint8_t* welcome, size_t length, const char** recognizedUserIds,
    size_t recognizedUserIdsLength);
void daveSessionGetMarshalledKeyPackage(DAVESessionHandle session,
    uint8_t** keyPackage, size_t* length);
DAVEKeyRatchetHandle daveSessionGetKeyRatchet(DAVESessionHandle session,
    const char* userId);
void daveSessionGetPairwiseFingerprint(DAVESessionHandle session, uint16_t version,
    const char* userId, DAVEPairwiseFingerprintCallback callback, void* userData);

void daveKeyRatchetDestroy(DAVEKeyRatchetHandle keyRatchet);

bool daveCommitResultIsFailed(DAVECommitResultHandle commitResultHandle);
bool daveCommitResultIsIgnored(DAVECommitResultHandle commitResultHandle);
void daveCommitResultGetRosterMemberIds(DAVECommitResultHandle commitResultHandle,
    uint64_t** rosterIds, size_t* rosterIdsLength);
void daveCommitResultGetRosterMemberSignature(DAVECommitResultHandle commitResultHandle,
    uint64_t rosterId, uint8_t** signature, size_t* signatureLength);
void daveCommitResultDestroy(DAVECommitResultHandle commitResultHandle);

void daveWelcomeResultGetRosterMemberIds(DAVEWelcomeResultHandle welcomeResultHandle,
    uint64_t** rosterIds, size_t* rosterIdsLength);
void daveWelcomeResultGetRosterMemberSignature(DAVEWelcomeResultHandle welcomeResultHandle,
    uint64_t rosterId, uint8_t** signature, size_t* signatureLength);
void daveWelcomeResultDestroy(DAVEWelcomeResultHandle welcomeResultHandle);

DAVEEncryptorHandle daveEncryptorCreate(void);
void daveEncryptorDestroy(DAVEEncryptorHandle encryptor);
void daveEncryptorSetKeyRatchet(DAVEEncryptorHandle encryptor, DAVEKeyRatchetHandle keyRatchet);
void daveEncryptorSetPassthroughMode(DAVEEncryptorHandle encryptor, bool passthroughMode);
void daveEncryptorAssignSsrcToCodec(DAVEEncryptorHandle encryptor, uint32_t ssrc,
    DAVECodec codecType);
uint16_t daveEncryptorGetProtocolVersion(DAVEEncryptorHandle encryptor);
size_t daveEncryptorGetMaxCiphertextByteSize(DAVEEncryptorHandle encryptor,
    DAVEMediaType mediaType, size_t frameSize);
bool daveEncryptorHasKeyRatchet(DAVEEncryptorHandle encryptor);
bool daveEncryptorIsPassthroughMode(DAVEEncryptorHandle encryptor);
DAVEEncryptorResultCode daveEncryptorEncrypt(DAVEEncryptorHandle encryptor,
    DAVEMediaType mediaType, uint32_t ssrc, const uint8_t* frame, size_t frameLength,
    uint8_t* encryptedFrame, size_t encryptedFrameCapacity, size_t* bytesWritten);
void daveEncryptorSetProtocolVersionChangedCallback(DAVEEncryptorHandle encryptor,
    DAVEEncryptorProtocolVersionChangedCallback callback, void* userData);
void daveEncryptorGetStats(DAVEEncryptorHandle encryptor, DAVEMediaType mediaType,
    DAVEEncryptorStats* stats);

DAVEDecryptorHandle daveDecryptorCreate(void);
void daveDecryptorDestroy(DAVEDecryptorHandle decryptor);
void daveDecryptorTransitionToKeyRatchet(DAVEDecryptorHandle decryptor,
    DAVEKeyRatchetHandle keyRatchet);
void daveDecryptorTransitionToPassthroughMode(DAVEDecryptorHandle decryptor,
    bool passthroughMode);
DAVEDecryptorResultCode daveDecryptorDecrypt(DAVEDecryptorHandle decryptor,
    DAVEMediaType mediaType, const uint8_t* encryptedFrame, size_t encryptedFrameLength,
    uint8_t* frame, size_t frameCapacity, size_t* bytesWritten);
size_t daveDecryptorGetMaxPlaintextByteSize(DAVEDecryptorHandle decryptor,
    DAVEMediaType mediaType, size_t encryptedFrameSize);
void daveDecryptorGetStats(DAVEDecryptorHandle decryptor, DAVEMediaType mediaType,
    DAVEDecryptorStats* stats);

void daveSetLogSinkCallback(DAVELogSinkCallback callback);
]]

local function load_dave()
    if not ffi_ok then
        return
    end

    if dave_lib then
        return
    end

    -- Unlike crypto.lua's load_sodium (Windows-only bundled path,
    -- libsodium expected as a system package on Linux/macOS), libdave is
    -- not expected to be installed system-wide anywhere, so this checks
    -- lib/dlls/ on both Windows and Linux (see native_lib.resolve_any_platform).
    -- Falls back to the bare name in case a system libdave does exist
    -- (e.g. manually installed), or on macOS where nothing is bundled.
    local bundled_path = native_lib.resolve_any_platform("libdave")

    local success = pcall(function()
        if bundled_path then
            dave_lib = ffi.load(bundled_path)
        else
            dave_lib = ffi.load("dave")
        end
    end)

    if not success or not dave_lib then
        dave_lib = nil
        return
    end

    local decl_ok = pcall(ffi.cdef, CDEF)
    if not decl_ok then
        dave_lib = nil
        return
    end

    dave_ready = true

    -- libdave logs internally (session.cpp etc) regardless of our own
    -- DEBUG flag in voice_gateway.lua. Passing a NULL function pointer
    -- here was tried first and had no effect on those session.cpp
    -- lines (they may be hardcoded stdout writes not routed through
    -- this sink at all), so a real callback is installed instead,
    -- printing severity WARNING and above: this is a live diagnostic
    -- aid for the decrypt-always-fails investigation (result code 1,
    -- DECRYPTION_FAILURE, with all of libdave's own missing-key/
    -- invalid-nonce counters at zero) -- everything on the Lua side has
    -- been checked byte-for-byte against davey's reference flow, so the
    -- remaining unknown is whatever libdave itself logs internally when
    -- an MLS/crypto operation doesn't do what's expected. The cdata
    -- callback is kept alive on dave_log_sink so the GC never collects
    -- it out from under libdave's held pointer.
    local log_sink_ok, log_sink = pcall(function()
        return ffi.cast("DAVELogSinkCallback", function(severity, file, line, message)
        end)
    end)

    if log_sink_ok and log_sink then
        dave_log_sink = log_sink
        pcall(function()
            dave_lib.daveSetLogSinkCallback(log_sink)
        end)
    end
end

load_dave()

local M = {
    lib = dave_lib,
    log_sink = dave_log_sink,
}

function M.available()
    return dave_ready
end

function M.max_supported_protocol_version()
    if not dave_ready then
        return nil, "libdave not available"
    end

    local ok, version = pcall(function()
        return dave_lib.daveMaxSupportedProtocolVersion()
    end)

    if not ok then
        return nil, "daveMaxSupportedProtocolVersion failed"
    end

    return tonumber(version)
end

-- Diagnostic: computes the same pairwise fingerprint ("Voice Privacy
-- Code") the official Discord client shows in its UI for a given user,
-- via daveSessionGetPairwiseFingerprint. The C API delivers the result
-- through a callback that libdave may invoke asynchronously (observed:
-- not necessarily synchronous with this call returning), so the
-- ffi.cast'd callback trampoline is intentionally NEVER freed here --
-- freeing/GCing it right after the call, before libdave has actually
-- invoked it, corrupts the callback and crashes the whole process
-- (observed: "PANIC: unprotected error ... bad callback"). This leaks
-- one small C closure per call, which is acceptable for a diagnostic
-- helper invoked at most once or twice per session, never in a hot
-- path.
--
-- Fire-and-forget contract: on_result(hex_string_or_nil, err_or_nil) is
-- called whenever the callback actually fires, which may be during
-- this call or some time after it returns. This function itself
-- returns true, nil immediately once the call is dispatched (or false,
-- err if dispatch itself failed synchronously), it does NOT wait for
-- on_result.
function M.get_pairwise_fingerprint(session_handle, version, user_id, on_result)
    if not dave_ready then
        return false, "libdave not available"
    end

    local callback
    callback = ffi.cast("DAVEPairwiseFingerprintCallback", function(fingerprint, length, user_data)
        local result_hex
        if fingerprint ~= nil and tonumber(length) > 0 then
            local hex_parts = {}
            for i = 1, tonumber(length) do
                hex_parts[i] = string.format("%02x", fingerprint[i - 1])
            end
            result_hex = table.concat(hex_parts)
        else
            result_hex = ""
        end
        if on_result then
            on_result(result_hex, nil)
        end
    end)

    local ok, err = pcall(function()
        dave_lib.daveSessionGetPairwiseFingerprint(session_handle, version, tostring(user_id), callback, nil)
    end)

    if not ok then
        if on_result then
            on_result(nil, "daveSessionGetPairwiseFingerprint failed: " .. tostring(err))
        end
        return false, "daveSessionGetPairwiseFingerprint failed: " .. tostring(err)
    end

    return true
end

return M
