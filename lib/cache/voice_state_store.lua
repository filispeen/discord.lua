-- lib/cache/voice_state_store.lua
-- Tracks each member's current voice channel per guild, built from
-- VOICE_STATE_UPDATE gateway dispatch events.
--
-- Public Contract:
--   VoiceStateStore.new(max_entries?) -> VoiceStateStore
--
--   VoiceStateStore:update(data) -> nil
--     data: a VOICE_STATE_UPDATE payload ({guild_id, user_id, channel_id, ...}).
--     Stores the state if channel_id is set, removes it if channel_id is
--     nil/null (user left voice or disconnected).
--
--   VoiceStateStore:get(guild_id, user_id) -> table or nil
--     Returns the last known voice state {channel_id, guild_id, user_id,
--     session_id, deaf, mute, self_deaf, self_mute}, or nil if the user
--     is not known to be in voice.
--
--   VoiceStateStore:get_channel_id(guild_id, user_id) -> string or nil
--     Convenience accessor for the channel_id field only.

local create_cache = require("cache.store")

-- Discord sends channel_id: null (JSON null) when a user leaves voice.
-- The luvit json library decodes JSON null to its own sentinel table
-- (json.null), not Lua nil, so both must be treated as "left voice".
local ok_json, json = pcall(require, "json")
local JSON_NULL = ok_json and json.null or nil

local function is_null(value)
    return value == nil or (JSON_NULL ~= nil and value == JSON_NULL)
end

local VoiceStateStore = {}
VoiceStateStore.__index = VoiceStateStore

local function key(guild_id, user_id)
    return tostring(guild_id) .. ":" .. tostring(user_id)
end

function VoiceStateStore.new(max_entries)
    local self = setmetatable({
        cache = create_cache(max_entries or 10000),
    }, VoiceStateStore)
    return self
end

function VoiceStateStore:update(data)
    if not data or not data.guild_id or not data.user_id then
        return
    end

    local cache_key = key(data.guild_id, data.user_id)

    if is_null(data.channel_id) then
        self.cache.remove(cache_key)
        return
    end

    self.cache.put(cache_key, {
        guild_id   = data.guild_id,
        user_id    = data.user_id,
        channel_id = data.channel_id,
        session_id = data.session_id,
        deaf       = data.deaf,
        mute       = data.mute,
        self_deaf  = data.self_deaf,
        self_mute  = data.self_mute,
    })
end

function VoiceStateStore:get(guild_id, user_id)
    return self.cache.get(key(guild_id, user_id))
end

function VoiceStateStore:get_channel_id(guild_id, user_id)
    local state = self:get(guild_id, user_id)
    return state and state.channel_id
end

return VoiceStateStore
