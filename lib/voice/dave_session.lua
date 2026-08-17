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
--   session:set_passthrough_mode(enabled) -- forwards to the encryptor
--     and every peer decryptor currently open; used during downgrade/
--     recovery
--   session:encrypt_opus(ssrc, plaintext) -> ciphertext or nil, err
--   session:decrypt_opus(user_id, ciphertext) -> plaintext or nil, err
--     -- uses that user_id's own decryptor handle (see
--     _get_or_create_decryptor); most callers should use
--     decrypt_opus_for_user(user_id, ciphertext) instead, which also
--     fetches/wires up the ratchet on first contact with a user_id
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

-- Displayable Code algorithm from the DAVE protocol whitepaper
-- (https://github.com/discord/dave-protocol/blob/main/protocol.md
-- #displayable-codes), used to render both the epoch authenticator and
-- pairwise verification fingerprints the same way official Discord
-- clients do, so a hex fingerprint from debug_pairwise_fingerprint can
-- be compared digit-for-digit against a peer's "View Voice Privacy
-- Code" UI (9 groups of 5 digits, 45 digits total, for the 64-byte
-- pairwise fingerprint).
--
-- hex_string: lowercase hex digest, group_size in {1..7}, code_length
-- must be a multiple of group_size and <= #hex_string/2.
local function displayable_code(hex_string, code_length, group_size)
    assert(#hex_string % 2 == 0, "hex_string must have an even number of hex digits")
    local byte_len = #hex_string / 2
    assert(byte_len >= code_length, "input data shorter than desired code length")
    assert(code_length % group_size == 0, "code_length must be a multiple of group_size")
    assert(group_size < 8, "group_size must be smaller than 8")

    local bytes = {}
    for i = 1, byte_len do
        bytes[i] = tonumber(hex_string:sub(i * 2 - 1, i * 2), 16)
    end

    local modulus = 10 ^ group_size
    local groups = code_length / group_size
    local parts = {}

    local byte_index = 1
    for _ = 1, groups do
        local value = 0
        for _ = 1, group_size do
            value = value * 256 + bytes[byte_index]
            byte_index = byte_index + 1
        end
        local group_value = value % modulus
        parts[#parts + 1] = string.format("%0" .. group_size .. "d", group_value)
    end

    return table.concat(parts)
end

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
    -- One DAVEDecryptorHandle PER PEER, keyed by user_id, not a single
    -- shared handle. libdave's C++ IDecryptor keeps its key ratchets in
    -- a single cryptorManagers_ deque (see decryptor.cpp); transitioning
    -- one shared decryptor between different peers' ratchets, as this
    -- code used to do, interleaves cryptor managers belonging to
    -- different users' ratchets in that same deque. Each cryptor
    -- manager tracks nonce/generation state independently per the
    -- ratchet that created it, so a decrypt attempt can walk through
    -- cryptor managers left behind by a *different* user's ratchet,
    -- derive *a* cryptor for the packet's generation from it anyway
    -- (generation numbering is local to each ratchet, so this "succeeds"
    -- at the lookup step), and only then fail AES-GCM tag verification
    -- because the key is simply wrong -- which is exactly the "no valid
    -- cryptor found" failure observed with a shared decryptor once a
    -- second peer's ratchet was ever transitioned onto it.
    -- davey (the reference Rust DAVE implementation used by
    -- @discordjs/voice) keeps one decryptor per user for the same
    -- reason -- see its CHANGELOG 0.1.4/0.1.5 entries about per-user
    -- decryptor lifecycle. self.decryptors[user_id] mirrors that.
    self.decryptors = {}
    self.key_ratchets = {}
    -- Local monotonic counter, incremented on every successful
    -- process_commit/process_welcome (i.e. every time libdave's MLS
    -- group actually advances to a new epoch). Not the real MLS epoch
    -- number (libdave's C API does not expose that directly to this
    -- file), but serves the same purpose for diagnosing timing/staleness:
    -- key_ratchet_epoch[user_id] records which value of this counter was
    -- current the last time that user's ratchet was fetched via
    -- refresh_key_ratchet. If a peer's cached ratchet was fetched under
    -- epoch_generation N, but the group has since advanced to N+1 via a
    -- later COMMIT/WELCOME without refresh_key_ratchet being called again
    -- for that peer, decrypt_opus_for_user's "already have a decryptor
    -- and ratchet" fast path (see its guard: `not decryptor or not
    -- self.key_ratchets[user_id]`) will keep reusing the now-stale
    -- generation-N ratchet against frames the peer is actually encrypting
    -- under generation N+1, which fails AEAD tag verification exactly
    -- like the observed "no valid cryptor found" -- looking wrong at the
    -- generation/nonce layer but actually wrong at the epoch layer.
    self.epoch_generation = 0
    self.key_ratchet_epoch = {}
    -- Set of user_id strings (keys, values all true) libdave itself
    -- reported as MLS group members as of the last COMMIT or WELCOME
    -- roster dump (see _record_mls_roster below). nil until the first
    -- COMMIT/WELCOME. Compared against voice_gateway's known_users
    -- (built from ops 11/12/13) in refresh_all_known_ratchets, to catch
    -- a local-MLS-group-vs-voice-gateway-membership desync directly
    -- instead of only inferring it from downstream decrypt failures.
    self.last_mls_roster = nil

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

    if not enc_ok or encryptor == nil then
        self.lib.daveSessionDestroy(self.handle)
        return nil, "daveEncryptorCreate failed"
    end

    self.encryptor = encryptor

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
    if os.getenv("DAVE_DEBUG_DUMP") then
        local gid = group_id_from_channel_id(self.channel_id)
        print("DAVE DUMP session_init protocol_version=" .. tostring(protocol_version)
            .. " channel_id=" .. self.channel_id
            .. " group_id_u64=" .. tostring(gid)
            .. " self_user_id=" .. self.user_id)
        io.stdout:flush()
    end
    self.lib.daveSessionInit(self.handle, protocol_version,
        group_id_from_channel_id(self.channel_id), self.user_id)
end

-- Re-creates the MLS group for a (possibly new) protocol_version, mirrors
-- pycord's reinit_dave_session: called whenever we get a fresh
-- session_description with dave_protocol_version > 0, or a
-- dave_prepare_epoch with epoch == 1 (brand new group).
function DaveSession:reinit(protocol_version)
    self.protocol_version = protocol_version
    if os.getenv("DAVE_DEBUG_DUMP") then
        local gid = group_id_from_channel_id(self.channel_id)
        print("DAVE DUMP session_reinit protocol_version=" .. tostring(protocol_version)
            .. " channel_id=" .. self.channel_id
            .. " group_id_u64=" .. tostring(gid)
            .. " self_user_id=" .. self.user_id
            .. " prev_epoch_generation=" .. self.epoch_generation)
        io.stdout:flush()
    end
    self.lib.daveSessionInit(self.handle, protocol_version,
        group_id_from_channel_id(self.channel_id), self.user_id)
    -- A fresh daveSessionInit call replaces the underlying MLS group
    -- entirely, so any epoch_generation stamps recorded against the
    -- previous group (see refresh_key_ratchet/_record_mls_roster) are
    -- meaningless for whatever group this reinit produces. Reset the
    -- counter and per-user stamps so a later staleness check never
    -- compares generations from two unrelated group lifetimes. NOTE:
    -- this does NOT destroy self.decryptors/self.key_ratchets handles
    -- themselves (existing behavior, unchanged here) -- only the new
    -- epoch-tracking bookkeeping added for staleness diagnosis.
    self.epoch_generation = 0
    self.key_ratchet_epoch = {}
end

function DaveSession:reset()
    self.lib.daveSessionReset(self.handle)
    self.protocol_version = 0

    -- Tear down every per-user decryptor and cached ratchet -- the MLS
    -- group is being wiped, so key material derived from the old group
    -- state is no longer valid for anyone, including peers who might
    -- rejoin under the same user_id in a future group.
    for user_id, decryptor in pairs(self.decryptors) do
        self.lib.daveDecryptorDestroy(decryptor)
        self.decryptors[user_id] = nil
    end
    for user_id, ratchet in pairs(self.key_ratchets) do
        self.lib.daveKeyRatchetDestroy(ratchet)
        self.key_ratchets[user_id] = nil
    end
    -- The MLS group is gone, so any epoch_generation stamps recorded
    -- against it are meaningless for whatever group comes next (a
    -- fresh reinit starts counting from 0 again in the real MLS epoch
    -- numbering too, conceptually). Reset both so a later staleness
    -- check never compares stamps from two unrelated groups.
    self.epoch_generation = 0
    self.key_ratchet_epoch = {}
    self.last_mls_roster = nil
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

-- Stores the given list of roster member id strings (already converted
-- from uint64_t by the caller) as self.last_mls_roster, a set keyed by
-- user_id string so refresh_all_known_ratchets can do an O(1) lookup
-- against it. Called from both process_commit and process_welcome
-- right after their respective roster dumps, so self.last_mls_roster
-- always reflects whichever of COMMIT/WELCOME landed most recently,
-- matching how libdave itself only keeps one current epoch's roster.
--
-- Also advances self.epoch_generation, since this is called exactly
-- once per successful group-establishing/advancing event (a real MLS
-- epoch change), giving refresh_key_ratchet a cheap local counter to
-- stamp each cached ratchet with (see epoch_generation's declaration
-- in DaveSession.new for why this matters for staleness detection).
function DaveSession:_record_mls_roster(id_strings)
    local roster = {}
    for _, id_str in ipairs(id_strings) do
        roster[id_str] = true
    end
    self.last_mls_roster = roster
    self.epoch_generation = self.epoch_generation + 1
    if os.getenv("DAVE_DEBUG_DUMP") then
        print("DAVE DUMP epoch_generation advanced to " .. self.epoch_generation
            .. " roster=" .. table.concat(id_strings, ","))
        io.stdout:flush()
    end
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

    -- Diagnostic: same rationale as process_welcome's roster dump
    -- below -- confirms our local MLS group actually contains the
    -- peer(s) we expect media from after this commit, rather than
    -- assuming recognized_user_ids matches what libdave settled on.
    if not failed and not ignored then
        local roster_ok, roster_err = pcall(function()
            local ids_ptr = ffi.new("uint64_t*[1]")
            local ids_len = ffi.new("size_t[1]")
            self.lib.daveCommitResultGetRosterMemberIds(result, ids_ptr, ids_len)
            local n = tonumber(ids_len[0])
            local parts = {}
            for i = 0, n - 1 do
                parts[#parts + 1] = string.format("%u", ids_ptr[0][i])
            end
            print("DAVE DEBUG COMMIT roster_member_ids=" .. table.concat(parts, ","))
            self:_record_mls_roster(parts)
            if ids_ptr[0] ~= nil then
                self.lib.daveFree(ids_ptr[0])
            end
        end)
        if not roster_ok then
            print("DAVE DEBUG COMMIT roster dump failed: " .. tostring(roster_err))
        end
    end

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

    -- Diagnostic: dump the actual MLS roster libdave built from this
    -- welcome, not just the recognized_user_ids we handed it. If a
    -- peer we expect media from (e.g. the one failing decrypt with
    -- "no valid cryptor found") is missing here, our local MLS group
    -- genuinely disagrees with the group Discord's voice gateway
    -- considers current -- daveSessionGetKeyRatchet(peer) would then
    -- derive a ratchet from OUR (wrong) epoch/state, which cannot
    -- match what that peer's real sender is encrypting with, no
    -- matter how correctly the Lua-side handle plumbing behaves.
    local roster_ok, roster_err = pcall(function()
        local ids_ptr = ffi.new("uint64_t*[1]")
        local ids_len = ffi.new("size_t[1]")
        self.lib.daveWelcomeResultGetRosterMemberIds(result, ids_ptr, ids_len)
        local n = tonumber(ids_len[0])
        local parts = {}
        for i = 0, n - 1 do
            parts[#parts + 1] = string.format("%u", ids_ptr[0][i])
        end
        print("DAVE DEBUG WELCOME roster_member_ids=" .. table.concat(parts, ","))
        self:_record_mls_roster(parts)
        if ids_ptr[0] ~= nil then
            self.lib.daveFree(ids_ptr[0])
        end
    end)
    if not roster_ok then
        print("DAVE DEBUG WELCOME roster dump failed: " .. tostring(roster_err))
    end

    self.lib.daveWelcomeResultDestroy(result)
    return true
end

-- Returns the DAVEDecryptorHandle for user_id, creating one via
-- daveDecryptorCreate() the first time this user is seen. Each peer
-- gets their own decryptor handle -- see the comment in
-- DaveSession.new for why a single shared decryptor across peers is
-- wrong (it was the actual root cause of the "no valid cryptor found"
-- failures this replaced).
function DaveSession:_get_or_create_decryptor(user_id)
    local decryptor = self.decryptors[user_id]
    if decryptor then
        return decryptor
    end

    local ok, new_decryptor = pcall(function()
        return self.lib.daveDecryptorCreate()
    end)
    if not ok or new_decryptor == nil then
        return nil
    end

    self.decryptors[user_id] = new_decryptor
    return new_decryptor
end

-- Fetches user_id's key ratchet for the current MLS epoch and wires it
-- up:
--   - for our own user_id, sets it on self.encryptor (we only ever
--     encrypt with our own ratchet)
--   - for a peer, transitions that peer's own decryptor handle
--     (created via _get_or_create_decryptor) onto it
--
-- Call this once per user per epoch, right after a WELCOME/COMMIT/
-- EXECUTE_TRANSITION confirms the new epoch is live (see
-- refresh_all_known_ratchets below), or lazily from
-- decrypt_opus_for_user for a peer not covered by that eager pass
-- (e.g. a very recent joiner).
function DaveSession:refresh_key_ratchet(user_id)
    user_id = user_id or self.user_id

    local old = self.key_ratchets[user_id]

    local user_id_str = tostring(user_id)
    if self._dave_debug_count == nil then
        self._dave_debug_count = 0
    end
    if self._dave_debug_count <= 200 then
        self._dave_debug_count = self._dave_debug_count + 1
        local hex_parts = {}
        for i = 1, #user_id_str do
            hex_parts[i] = string.format("%02x", user_id_str:byte(i))
        end
        print("DAVE DEBUG refresh_key_ratchet user_id_str=" .. user_id_str
            .. " len=" .. #user_id_str
            .. " hex=" .. table.concat(hex_parts, " ")
            .. " is_self=" .. tostring(user_id_str == self.user_id))
        io.stdout:flush()
    end

    local ratchet_ok, ratchet = pcall(function()
        return self.lib.daveSessionGetKeyRatchet(self.handle, user_id_str)
    end)

    -- FFI cdata pointers for a struct handle type are not guaranteed to
    -- compare equal to Lua nil even when libdave returns a NULL C
    -- pointer (ffi.cast/typed pointer semantics), so `ratchet == nil`
    -- alone does not reliably detect "user not in group yet". Use
    -- ffi.NULL comparison via tonumber(ffi.cast) fallback: cast to
    -- intptr_t and check for zero, which catches a real NULL return
    -- from daveSessionGetKeyRatchet regardless of cdata comparison
    -- quirks.
    local is_null = (ratchet == nil)
    if not is_null and ffi then
        local addr_ok, addr = pcall(function()
            return tonumber(ffi.cast("intptr_t", ratchet))
        end)
        if addr_ok and addr == 0 then
            is_null = true
        end
    end

    if not ratchet_ok or is_null then
        return false, "daveSessionGetKeyRatchet returned no ratchet for user " .. tostring(user_id)
            .. " (not yet a member of the current MLS epoch)"
    end

    self.key_ratchets[user_id] = ratchet
    self.key_ratchet_epoch[user_id] = self.epoch_generation
    if os.getenv("DAVE_DEBUG_DUMP") then
        print("DAVE DUMP refresh_key_ratchet user=" .. tostring(user_id)
            .. " stamped_epoch_generation=" .. self.epoch_generation)
        io.stdout:flush()
    end

    if user_id == self.user_id then
        self.lib.daveEncryptorSetKeyRatchet(self.encryptor, ratchet)
    else
        -- Each peer owns their own decryptor handle, so transitioning
        -- it here onto this peer's ratchet can never disturb another
        -- peer's decryptor or its cryptorManagers_ state (unlike the
        -- old single shared self.decryptor, where transitioning onto
        -- peer B's ratchet left peer A's still-in-flight cryptor
        -- managers sitting in the same deque, alongside peer B's).
        local decryptor = self:_get_or_create_decryptor(user_id)
        if not decryptor then
            return false, "daveDecryptorCreate failed for user " .. tostring(user_id)
        end
        self.lib.daveDecryptorTransitionToKeyRatchet(decryptor, ratchet)
    end

    if old then
        self.lib.daveKeyRatchetDestroy(old)
    end

    return true
end

-- Proactively refreshes the key ratchet for every known peer, in
-- addition to our own, right after an epoch actually changes
-- (MLS_COMMIT_TRANSITION, MLS_WELCOME, DAVE_EXECUTE_TRANSITION). Each
-- peer's own decryptor (see _get_or_create_decryptor) is transitioned
-- immediately as part of refresh_key_ratchet -- there is no shared
-- decryptor state for this to race against or clobber between peers.
--
-- Without this eager fetch, a peer's ratchet would only ever be
-- fetched on their first RTP packet after the epoch change. That lazy
-- fetch races the C++ side: if the packet arrives before libdave has
-- fully committed the new epoch internally, daveSessionGetKeyRatchet
-- can return before the new sender ratchet is derivable for that
-- user, and the caller has no signal that anything went wrong until
-- decrypt fails downstream. Fetching eagerly here, right after the
-- transition that MLS_WELCOME/MLS_COMMIT_TRANSITION/EXECUTE_TRANSITION
-- all confirm has actually landed, removes that race for every user
-- we already know about. New joiners (not yet in known_user_ids)
-- still fall back to the lazy path in decrypt_opus_for_user, which is
-- correct since we can't fetch a ratchet for someone who isn't in the
-- group yet.
--
-- Returns a table of { [user_id] = ok_boolean } so callers can log
-- which peers failed, instead of only finding out on first decrypt.
-- Diagnostic: cross-checks known_user_ids (from voice_gateway's
-- known_users, ops 11/12/13) against self.last_mls_roster (libdave's
-- own COMMIT/WELCOME roster, see _record_mls_roster). These two lists
-- are expected to always agree; if they don't, daveSessionGetKeyRatchet
-- below is being asked for a user who either:
--   - is in known_user_ids but NOT in last_mls_roster: the voice
--     gateway thinks this user is in the channel, but our local MLS
--     group does not contain them yet/at all. refresh_key_ratchet will
--     correctly fail for them ("not yet a member of the current MLS
--     epoch") -- not a bug, just expected until their own COMMIT/WELCOME
--     lands, but worth knowing if it never resolves.
--   - is in last_mls_roster but NOT in known_user_ids: our local MLS
--     group contains a user refresh_all_known_ratchets will never even
--     attempt, because voice_gateway never told us about them via
--     11/12/13. Their key ratchet is simply never fetched/wired up, so
--     decrypt_opus_for_user's lazy fallback is the only thing that
--     could still catch them (see dave_session.lua's public contract
--     comment on decrypt_opus_for_user) -- if that also never fires for
--     this user, this is the actual desync causing their "no valid
--     cryptor found" failures, and it lives in voice_gateway.lua's
--     known_users bookkeeping (11/12/13 handling), not in the FFI/
--     handle plumbing here.
-- last_mls_roster is nil until the first COMMIT/WELCOME, in which case
-- there is nothing to compare against yet and this is a no-op.
function DaveSession:_check_roster_desync(known_user_ids)
    if not self.last_mls_roster then
        return
    end

    local known_set = {}
    for _, user_id in ipairs(known_user_ids or {}) do
        known_set[tostring(user_id)] = true
    end

    local only_in_known = {}
    for user_id in pairs(known_set) do
        if not self.last_mls_roster[user_id] then
            only_in_known[#only_in_known + 1] = user_id
        end
    end

    local only_in_roster = {}
    for user_id in pairs(self.last_mls_roster) do
        if not known_set[user_id] then
            only_in_roster[#only_in_roster + 1] = user_id
        end
    end

    if #only_in_known > 0 or #only_in_roster > 0 then
        print("DAVE DEBUG ROSTER DESYNC only_in_known_users="
            .. table.concat(only_in_known, ",")
            .. " only_in_mls_roster=" .. table.concat(only_in_roster, ","))
        io.stdout:flush()
    end
end

function DaveSession:refresh_all_known_ratchets(known_user_ids)
    self:_check_roster_desync(known_user_ids)

    local results = {}
    for _, user_id in ipairs(known_user_ids or {}) do
        if tostring(user_id) ~= self.user_id then
            local ok, err = self:refresh_key_ratchet(user_id)
            results[tostring(user_id)] = ok
            if not ok then
                print("DAVE DEBUG refresh_all_known_ratchets FAILED user_id=" .. tostring(user_id)
                    .. " err=" .. tostring(err))
            end
        end
    end
    return results
end

-- Passthrough mode is set per-decryptor in libdave's C API, so this
-- has to loop over every peer's decryptor, not just one shared handle.
-- Newly-seen peers created after this call (via _get_or_create_decryptor)
-- won't have passthrough applied retroactively; decrypt_opus_for_user
-- re-applies self._passthrough_enabled when it creates a fresh
-- decryptor for that reason.
function DaveSession:set_passthrough_mode(enabled)
    self.lib.daveEncryptorSetPassthroughMode(self.encryptor, enabled)
    self._passthrough_enabled = enabled
    for _, decryptor in pairs(self.decryptors) do
        self.lib.daveDecryptorTransitionToPassthroughMode(decryptor, enabled)
    end
end

function DaveSession:assign_ssrc_to_opus(ssrc)
    local ok, err = pcall(function()
        self.lib.daveEncryptorAssignSsrcToCodec(self.encryptor, ssrc, self.lib.DAVE_CODEC_OPUS or 1)
    end)
    if not ok then
        return false, err
    end
    return true
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

-- Decrypts an incoming Opus RTP payload from a specific sender, using
-- that sender's own decryptor handle (see _get_or_create_decryptor and
-- the comment in DaveSession.new for why each peer needs one). If we
-- have no cached ratchet for this user yet (a very recent joiner not
-- covered by the last refresh_all_known_ratchets call), falls back to
-- refresh_key_ratchet, which both fetches the ratchet and wires up
-- this user's decryptor as a side effect.
function DaveSession:decrypt_opus_for_user(user_id, ciphertext)
    user_id = tostring(user_id)

    local decryptor = self.decryptors[user_id]
    if not decryptor or not self.key_ratchets[user_id] then
        local ok, err = self:refresh_key_ratchet(user_id)
        if not ok then
            return nil, err
        end
        decryptor = self.decryptors[user_id]
        if not decryptor then
            return nil, "ratchet refreshed but no decryptor created for user " .. user_id
        end
        -- A decryptor created just now via refresh_key_ratchet's
        -- _get_or_create_decryptor call starts in the C API's default
        -- (non-passthrough) mode; apply whatever passthrough state the
        -- rest of the session is currently in, so a peer who joins
        -- mid-transition doesn't get treated differently than peers
        -- whose decryptors already existed when set_passthrough_mode
        -- was last called.
        if self._passthrough_enabled then
            self.lib.daveDecryptorTransitionToPassthroughMode(decryptor, true)
        end
    end

    return self:decrypt_opus(user_id, ciphertext)
end

function DaveSession:decrypt_opus(user_id, ciphertext)
    user_id = tostring(user_id)
    if self._decrypt_userid_dump_count == nil then
        self._decrypt_userid_dump_count = 0
    end
    if self._decrypt_userid_dump_count <= 20 then
        self._decrypt_userid_dump_count = self._decrypt_userid_dump_count + 1
        local ratchet_key_present = self.key_ratchets[user_id] ~= nil
        local decryptor_key_present = self.decryptors[user_id] ~= nil
        print("DAVE DEBUG decrypt_opus user_id=" .. user_id
            .. " len=" .. #user_id
            .. " key_ratchets_has_key=" .. tostring(ratchet_key_present)
            .. " decryptors_has_key=" .. tostring(decryptor_key_present))
        io.stdout:flush()
    end
    local decryptor = self.decryptors[user_id]
    if not decryptor then
        return nil, "no decryptor for user " .. user_id
    end

    if os.getenv("DAVE_DEBUG_DUMP") and #ciphertext > 20 then
        local stamped_epoch = self.key_ratchet_epoch[user_id]
        local is_stale = stamped_epoch ~= nil and stamped_epoch ~= self.epoch_generation
        print("DAVE DUMP decrypt_opus_epoch_check user=" .. user_id
            .. " ratchet_stamped_epoch_generation=" .. tostring(stamped_epoch)
            .. " current_epoch_generation=" .. self.epoch_generation
            .. " STALE=" .. tostring(is_stale))
        io.stdout:flush()
    end

    if #ciphertext > 20 then
        self._decrypt_debug_count = (self._decrypt_debug_count or 0) + 1
        if self._decrypt_debug_count <= 200 then
            print("DAVE DEBUG decrypt_opus ENTER user=" .. user_id .. " ciphertext_len=" .. #ciphertext)
            io.stdout:flush()
        end
    end

    local max_size = self.lib.daveDecryptorGetMaxPlaintextByteSize(
        decryptor, 0, #ciphertext)  -- DAVE_MEDIA_TYPE_AUDIO = 0

    if self._decrypt_debug_count and self._decrypt_debug_count <= 200 and #ciphertext > 20 then
        local dump_ok, dump_err = pcall(function()
            local tail_len = math.min(20, #ciphertext)
            local tail = ciphertext:sub(#ciphertext - tail_len + 1)
            local hex_parts = {}
            for i = 1, #tail do
                hex_parts[i] = string.format("%02x", tail:byte(i))
            end
            print("DAVE DEBUG decrypt_opus max_size=" .. tostring(tonumber(max_size))
                .. " ciphertext_len=" .. #ciphertext
                .. " ratchet_ptr=" .. tostring(self.key_ratchets[user_id])
                .. " user=" .. user_id
                .. " tail_hex=" .. table.concat(hex_parts, " "))
            io.stdout:flush()
        end)
        if not dump_ok then
            print("DAVE DEBUG decrypt_opus dump_error=" .. tostring(dump_err))
            io.stdout:flush()
        end

        if os.getenv("DAVE_DEBUG_DUMP") then
            local full_ok, full_err = pcall(function()
                local hex_parts = {}
                for i = 1, #ciphertext do
                    hex_parts[i] = string.format("%02x", ciphertext:byte(i))
                end
                print("DAVE DUMP decrypt_frame_full user=" .. user_id
                    .. " len=" .. #ciphertext
                    .. " hex=" .. table.concat(hex_parts))
                io.stdout:flush()
            end)
            if not full_ok then
                print("DAVE DEBUG decrypt_opus full dump_error=" .. tostring(full_err))
                io.stdout:flush()
            end
        end
    end

    local out_buf = ffi.new("uint8_t[?]", max_size)
    local written = ffi.new("size_t[1]")
    local frame = ffi.cast("const uint8_t*", ciphertext)

    local result = self.lib.daveDecryptorDecrypt(decryptor, 0,
        frame, #ciphertext, out_buf, max_size, written)

    if result ~= 0 then  -- DAVE_DECRYPTOR_RESULT_CODE_SUCCESS = 0
        return nil, "dave decrypt failed, result code " .. tostring(tonumber(result))
    end

    return ffi.string(out_buf, tonumber(written[0]))
end

-- Diagnostic snapshot of a specific peer decryptor's internal counters
-- (see DAVEDecryptorStats in dave_ffi.lua). Useful to disambiguate a
-- generic DECRYPTION_FAILURE result code from missing-key or
-- invalid-nonce conditions the decryptor tracks separately but doesn't
-- surface via the plain result code from daveDecryptorDecrypt.
function DaveSession:get_decryptor_stats(user_id)
    local decryptor = self.decryptors[tostring(user_id)]
    if not decryptor then
        return nil, "no decryptor for user " .. tostring(user_id)
    end
    local stats = ffi.new("DAVEDecryptorStats")
    self.lib.daveDecryptorGetStats(decryptor, 0, stats)  -- DAVE_MEDIA_TYPE_AUDIO = 0
    return {
        passthroughCount = tonumber(stats.passthroughCount),
        decryptSuccessCount = tonumber(stats.decryptSuccessCount),
        decryptFailureCount = tonumber(stats.decryptFailureCount),
        decryptDuration = tonumber(stats.decryptDuration),
        decryptAttempts = tonumber(stats.decryptAttempts),
        decryptMissingKeyCount = tonumber(stats.decryptMissingKeyCount),
        decryptInvalidNonceCount = tonumber(stats.decryptInvalidNonceCount),
    }
end

-- Diagnostic self-loopback test: encrypts a test frame with our own
-- encryptor ratchet, then attempts to decrypt it back using a SEPARATE
-- decryptor handle transitioned to our own key ratchet (fetched fresh
-- via daveSessionGetKeyRatchet for self.user_id, same call path
-- refresh_key_ratchet uses for peers). Uses a throwaway decryptor
-- handle instead of self.decryptor so the currently active peer
-- ratchet on the real decryptor is never touched, making this safe to
-- call mid-session without disturbing live peer decrypt state.
-- Returns ok, err_or_nil. ok == true means our own encrypt/derive/
-- decrypt round-trip works correctly, isolating any live-peer
-- DecryptionFailure to something peer/derivation-specific rather than
-- a fundamental bug in our mlspp/derivation or AEAD call path.
function DaveSession:debug_self_loopback_test()
    if not self:ready() then
        return false, "encryptor has no key ratchet yet"
    end

    if self._dave_debug_double_fetch_done == nil then
        self._dave_debug_double_fetch_done = true
        local ok1, ratchet1 = pcall(function()
            return self.lib.daveSessionGetKeyRatchet(self.handle, self.user_id)
        end)
        local ok2, ratchet2 = pcall(function()
            return self.lib.daveSessionGetKeyRatchet(self.handle, self.user_id)
        end)
        local addr1 = (ok1 and ratchet1 and ffi) and tonumber(ffi.cast("intptr_t", ratchet1)) or nil
        local addr2 = (ok2 and ratchet2 and ffi) and tonumber(ffi.cast("intptr_t", ratchet2)) or nil
        print("DAVE DEBUG double_fetch self ok1=" .. tostring(ok1) .. " addr1=" .. tostring(addr1)
            .. " ok2=" .. tostring(ok2) .. " addr2=" .. tostring(addr2)
            .. " same_addr=" .. tostring(addr1 == addr2))
        io.stdout:flush()
        if ok1 and ratchet1 then
            self.lib.daveKeyRatchetDestroy(ratchet1)
        end
        if ok2 and ratchet2 then
            self.lib.daveKeyRatchetDestroy(ratchet2)
        end
    end

    local test_ssrc = 1
    local test_plaintext = "dave-self-loopback-test-payload-0123456789"

    local ciphertext, enc_err = self:encrypt_opus(test_ssrc, test_plaintext)
    if not ciphertext then
        return false, "encrypt_opus failed: " .. tostring(enc_err)
    end

    local ratchet_ok, ratchet = pcall(function()
        return self.lib.daveSessionGetKeyRatchet(self.handle, tostring(self.user_id))
    end)
    if not ratchet_ok or ratchet == nil then
        return false, "daveSessionGetKeyRatchet(self) failed for loopback"
    end

    local temp_decryptor_ok, temp_decryptor = pcall(function()
        return self.lib.daveDecryptorCreate()
    end)
    if not temp_decryptor_ok or temp_decryptor == nil then
        self.lib.daveKeyRatchetDestroy(ratchet)
        return false, "daveDecryptorCreate (temp) failed for loopback"
    end

    self.lib.daveDecryptorTransitionToKeyRatchet(temp_decryptor, ratchet)

    local max_size = self.lib.daveDecryptorGetMaxPlaintextByteSize(
        temp_decryptor, 0, #ciphertext)
    local out_buf = ffi.new("uint8_t[?]", max_size)
    local written = ffi.new("size_t[1]")
    local frame = ffi.cast("const uint8_t*", ciphertext)

    local result = self.lib.daveDecryptorDecrypt(temp_decryptor, 0,
        frame, #ciphertext, out_buf, max_size, written)

    self.lib.daveDecryptorDestroy(temp_decryptor)
    self.lib.daveKeyRatchetDestroy(ratchet)

    if result ~= 0 then
        return false, "self-loopback decrypt failed, result code " .. tostring(tonumber(result))
    end

    local decrypted = ffi.string(out_buf, tonumber(written[0]))
    if decrypted ~= test_plaintext then
        return false, "self-loopback decrypted payload mismatch: got " .. tostring(decrypted)
    end

    return true
end

-- Diagnostic: computes the pairwise fingerprint ("Voice Privacy Code")
-- for a given peer user_id, the same value the official Discord client
-- displays in its UI. Fire-and-forget: on_result(hex_or_nil, err_or_nil)
-- is invoked whenever libdave's callback actually fires, which may not
-- be synchronous with this call (see dave_ffi.get_pairwise_fingerprint).
-- Useful to confirm this session's MLS group state actually agrees
-- with a specific peer at the protocol level, since a computable,
-- stable fingerprint here means the roster/epoch state for that
-- user_id is coherent from libdave's perspective, independent of
-- whether decrypt_opus later succeeds for their media frames.
function DaveSession:debug_pairwise_fingerprint(user_id, on_result, version)
    version = version or self.protocol_version
    return dave_ffi.get_pairwise_fingerprint(self.handle, version, tostring(user_id), on_result)
end

-- Diagnostic: same as debug_pairwise_fingerprint, but formats the
-- resulting 64-byte hex fingerprint as the 45-digit displayable code
-- (9 groups of 5 digits) official Discord clients show under "View
-- Voice Privacy Code" for a given user in the call. Prints the code
-- directly to stdout so it can be read off and compared by hand
-- against the peer's client, without wiring up any extra UI.
--
-- If the printed code here does NOT match what the peer's official
-- Discord client displays for you, the MLS group state itself has
-- diverged (wrong epoch, wrong roster, wrong commit applied) and the
-- problem is upstream of key ratchets entirely -- this must be fixed
-- before decrypt_opus failures are worth chasing further. If it DOES
-- match, MLS/roster state is confirmed coherent and the failure is
-- isolated to the SSRC->user_id->decryptor/ratchet wiring or to a
-- race between refresh_key_ratchet and the first incoming RTP packet.
function DaveSession:debug_pairwise_fingerprint_code(user_id, version)
    self:debug_pairwise_fingerprint(user_id, function(hex, err)
        if not hex or hex == "" then
            print("DAVE DEBUG fingerprint FAILED user=" .. tostring(user_id)
                .. " err=" .. tostring(err))
            io.stdout:flush()
            return
        end

        local ok, code = pcall(displayable_code, hex, 45, 5)
        if not ok then
            print("DAVE DEBUG fingerprint encode FAILED user=" .. tostring(user_id)
                .. " hex_len=" .. #hex .. " err=" .. tostring(code))
            io.stdout:flush()
            return
        end

        print("DAVE DEBUG fingerprint user=" .. tostring(user_id) .. " code=" .. code)
        print("DAVE DEBUG fingerprint user=" .. tostring(user_id) .. " raw_hex=" .. hex)
        io.stdout:flush()
    end, version)
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

    for user_id, decryptor in pairs(self.decryptors) do
        self.lib.daveDecryptorDestroy(decryptor)
        self.decryptors[user_id] = nil
    end

    if self.handle then
        self.lib.daveSessionDestroy(self.handle)
        self.handle = nil
    end
end

return DaveSession