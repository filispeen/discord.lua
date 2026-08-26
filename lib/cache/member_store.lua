-- lib/cache/member_store.lua
-- Tracks guild members, built from GUILD_CREATE's initial member list,
-- GUILD_MEMBERS_CHUNK, and GUILD_MEMBER_ADD/UPDATE/REMOVE gateway
-- dispatch events.
--
-- Public Contract:
--   MemberStore.new(max_entries?) -> MemberStore
--
--   MemberStore:put(guild_id, data) -> nil
--     data: a raw member payload ({user, nick, roles, joined_at, ...})
--     as received from Discord. Stores/overwrites the entry keyed by
--     guild_id + data.user.id.
--
--   MemberStore:put_many(guild_id, members) -> nil
--     members: array of raw member payloads (as sent in GUILD_CREATE's
--     .members field or GUILD_MEMBERS_CHUNK's .members field).
--
--   MemberStore:get(guild_id, user_id) -> table or nil
--     Returns the last known raw member payload for that user in that
--     guild, or nil if never seen or removed.
--
--   MemberStore:remove(guild_id, user_id) -> nil
--     Drops the member from the store (GUILD_MEMBER_REMOVE).
--
--   MemberStore:get_all(guild_id) -> table (array)
--     Returns all currently cached member payloads for a guild.

local create_cache = require("./store")

local MemberStore = {}
MemberStore.__index = MemberStore

local function key(guild_id, user_id)
    return tostring(guild_id) .. ":" .. tostring(user_id)
end

function MemberStore.new(max_entries)
    local self = setmetatable({
        cache = create_cache(max_entries or 10000),
        by_guild = {},
    }, MemberStore)
    return self
end

function MemberStore:put(guild_id, data)
    if not guild_id or not data or not data.user or not data.user.id then
        return
    end

    local user_id = data.user.id
    self.cache.put(key(guild_id, user_id), data)

    self.by_guild[guild_id] = self.by_guild[guild_id] or {}
    self.by_guild[guild_id][user_id] = true
end

function MemberStore:put_many(guild_id, members)
    if not guild_id or not members then
        return
    end
    for _, member_data in ipairs(members) do
        self:put(guild_id, member_data)
    end
end

function MemberStore:get(guild_id, user_id)
    if not guild_id or not user_id then
        return nil
    end
    return self.cache.get(key(guild_id, user_id))
end

function MemberStore:remove(guild_id, user_id)
    if not guild_id or not user_id then
        return
    end
    self.cache.remove(key(guild_id, user_id))
    if self.by_guild[guild_id] then
        self.by_guild[guild_id][user_id] = nil
    end
end

function MemberStore:get_all(guild_id)
    local result = {}
    local ids = self.by_guild[guild_id]
    if not ids then
        return result
    end
    for user_id in pairs(ids) do
        local member = self:get(guild_id, user_id)
        if member then
            table.insert(result, member)
        end
    end
    return result
end

return MemberStore
