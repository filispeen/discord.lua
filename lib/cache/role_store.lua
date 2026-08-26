-- lib/cache/role_store.lua
-- Tracks guild roles, built from GUILD_CREATE's initial role list and
-- GUILD_ROLE_CREATE/UPDATE/DELETE gateway dispatch events.
--
-- Public Contract:
--   RoleStore.new(max_entries?) -> RoleStore
--
--   RoleStore:put(guild_id, data) -> nil
--     data: a raw role payload ({id, name, permissions, ...}) as
--     received from Discord. Stores/overwrites the entry keyed by
--     guild_id + data.id.
--
--   RoleStore:put_many(guild_id, roles) -> nil
--     roles: array of raw role payloads (as sent in GUILD_CREATE's
--     .roles field).
--
--   RoleStore:get(guild_id, role_id) -> table or nil
--     Returns the last known raw role payload for that role in that
--     guild, or nil if never seen or removed.
--
--   RoleStore:remove(guild_id, role_id) -> nil
--     Drops the role from the store (GUILD_ROLE_DELETE).
--
--   RoleStore:get_all(guild_id) -> table (array)
--     Returns all currently cached role payloads for a guild.

local create_cache = require("./store")

local RoleStore = {}
RoleStore.__index = RoleStore

local function key(guild_id, role_id)
    return tostring(guild_id) .. ":" .. tostring(role_id)
end

function RoleStore.new(max_entries)
    local self = setmetatable({
        cache = create_cache(max_entries or 10000),
        by_guild = {},
    }, RoleStore)
    return self
end

function RoleStore:put(guild_id, data)
    if not guild_id or not data or not data.id then
        return
    end

    local role_id = data.id
    self.cache.put(key(guild_id, role_id), data)

    self.by_guild[guild_id] = self.by_guild[guild_id] or {}
    self.by_guild[guild_id][role_id] = true
end

function RoleStore:put_many(guild_id, roles)
    if not guild_id or not roles then
        return
    end
    for _, role_data in ipairs(roles) do
        self:put(guild_id, role_data)
    end
end

function RoleStore:get(guild_id, role_id)
    if not guild_id or not role_id then
        return nil
    end
    return self.cache.get(key(guild_id, role_id))
end

function RoleStore:remove(guild_id, role_id)
    if not guild_id or not role_id then
        return
    end
    self.cache.remove(key(guild_id, role_id))
    if self.by_guild[guild_id] then
        self.by_guild[guild_id][role_id] = nil
    end
end

function RoleStore:get_all(guild_id)
    local result = {}
    local ids = self.by_guild[guild_id]
    if not ids then
        return result
    end
    for role_id in pairs(ids) do
        local role = self:get(guild_id, role_id)
        if role then
            table.insert(result, role)
        end
    end
    return result
end

return RoleStore
