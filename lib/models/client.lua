-- lib/models/client.lua
-- Main client model for Discord.lua
--
-- Public Contract:
--   Client.new(token, ratelimiter) -> Client
--     Creates a new Discord client.
--
--   Client:http -> table
--     HTTP client instance.
--
--   Client:ratelimiter -> table
--     Rate limiter instance.
--
--   Client:on(event, callback) -> self
--     Subscribe to an event.
--
--   Client:once(event, callback) -> self
--     Subscribe to an event once.
--
--   Client:emit(event, ...) -> self
--     Emit an event.
--
--   Client:off(event, callback) -> self
--     Unsubscribe from an event.
--
--   Client:get_user(id) -> User
--     Get a user by ID.
--
--   Client:get_member(id) -> Member
--     Get a member by ID.
--
--   Client:get_channel(id) -> Channel or nil
--     Get a Channel by ID. Checks the channel cache first (populated from
--     GUILD_CREATE/CHANNEL_CREATE/CHANNEL_UPDATE dispatch events), falls
--     back to a REST GET /channels/{id} if not cached. The returned
--     Channel's .guild is a minimal {id = guild_id} stand-in, not a full
--     Guild object, since only the id is known from cached/REST channel
--     data; enough for Channel:connect()/VoiceClient which only read
--     channel.guild.id.
--
--   Client:get_role(id) -> Role
--     Get a role by ID.
--
--   Client:get_guild(id) -> Guild
--     Get a guild by ID.

local class = require("../core/class")

-- Client class
local Client = class("Client")

function Client.new(token, ratelimiter, intents)
    local enums = require("../core/enums")
    local VoiceStateStore = require("../cache/voice_state_store")
    local ChannelStore = require("../cache/channel_store")
    local MemberStore = require("../cache/member_store")
    local RoleStore = require("../cache/role_store")
    local self = {
        token = token,
        ratelimiter = ratelimiter or {},
        events = {},
        listeners = {},
        http = nil,
        rest = nil,
        gateway = nil,
        application_id = nil,
        intents = intents or enums.default_intents(),
        user = nil,
        voice_states = VoiceStateStore.new(),
        channels = ChannelStore.new(),
        members = MemberStore.new(),
        roles = RoleStore.new(),
    }
    setmetatable(self, {
        __index = Client
    })
    return self
end

-- Fetches and caches the application id needed for slash command sync.
function Client:get_application_id()
    if self.application_id then
        return self.application_id
    end
    if not self.http then
        return nil
    end
    local response = self.http:get("/oauth2/applications/@me")
    if response and response.id then
        self.application_id = response.id
    end
    return self.application_id
end

-- Generic GET passthrough to the underlying http client, used by
-- ShardManager:start() to fetch /gateway/bot.
function Client:get(endpoint)
    if not self.http then
        return nil
    end
    return self.http:get(endpoint)
end

-- Sends a voice state update (opcode 4) to join, move between, or leave
-- a voice channel. channel_id = nil disconnects. Requires the gateway to
-- be started (Client:start_gateway / Bot:run). This is the hook voice
-- and Lavalink integrations use as sendPayload.
function Client:voice_state_update(guild_id, channel_id, self_mute, self_deaf)
    if not self.gateway then
        error("Client:voice_state_update called before start_gateway()", 0)
    end
    return self.gateway:voice_state_update(guild_id, channel_id, self_mute, self_deaf)
end

-- Returns the last known voice state for a member in a guild, built
-- from VOICE_STATE_UPDATE dispatch events. nil if the member is not
-- known to be in a voice channel (never seen, or has since left).
function Client:get_voice_state(guild_id, user_id)
    return self.voice_states:get(guild_id, user_id)
end

-- Convenience accessor: just the voice channel id a member is
-- currently in, or nil.
function Client:get_voice_channel_id(guild_id, user_id)
    return self.voice_states:get_channel_id(guild_id, user_id)
end

-- Returns the last known raw member payload for a user in a guild,
-- built from GUILD_CREATE/GUILD_MEMBERS_CHUNK/GUILD_MEMBER_ADD/UPDATE
-- dispatch events. nil if the member has never been seen or has left.
function Client:get_cached_member(guild_id, user_id)
    return self.members:get(guild_id, user_id)
end

-- Returns all currently cached member payloads for a guild.
function Client:get_guild_members(guild_id)
    return self.members:get_all(guild_id)
end

-- Returns the last known raw role payload for a role in a guild,
-- built from GUILD_CREATE/GUILD_ROLE_CREATE/UPDATE dispatch events.
-- nil if the role has never been seen or has been deleted.
function Client:get_cached_role(guild_id, role_id)
    return self.roles:get(guild_id, role_id)
end

-- Returns all currently cached role payloads for a guild.
function Client:get_guild_roles(guild_id)
    return self.roles:get_all(guild_id)
end

-- Create HTTP client
function Client:_create_http()
    local ratelimiter = require("../http/ratelimiter")
    local client = require("../http/client")
    local Route = require("../http/route")

    local manager = ratelimiter.Manager.new()
    self.ratelimiter = manager

    local http_client = client.new(self.token, manager)
    self.http = http_client
    self.rest = Route.new(http_client)

    return http_client
end

-- Create and start gateway
function Client:start_gateway()
    local gateway_manager = require("../gateway/manager")

    self.gateway = gateway_manager.new(self, 1)

    -- Listen for gateway events
    self.gateway:on_shard_ready(function(shard_id, shard)
        self:emit("shard_ready", { shard_id = shard_id, shard = shard })
    end)

    self.gateway:on_shard_error(function(shard_id, shard, error)
        self:emit("shard_error", { shard_id = shard_id, shard = shard, error = error })
    end)

    self.gateway:on_shard_disconnect(function(shard_id, shard, event)
        self:emit("shard_disconnect", { shard_id = shard_id, shard = shard, event = event })
    end)

    self.gateway:on_ready(function(ready_payload)
        if ready_payload and ready_payload.user then
            self.user = ready_payload.user
        end
        self:emit("ready")
    end)

    self.gateway:on_dispatch("MESSAGE_CREATE", function(data)
        local Message = require("./message")
        self:emit("message_create", Message.new(data, self.http))
    end)

    self.gateway:on_dispatch("MESSAGE_UPDATE", function(data)
        local Message = require("./message")
        self:emit("message_update", Message.new(data, self.http))
    end)

    self.gateway:on_dispatch("MESSAGE_DELETE", function(data)
        self:emit("message_delete", data)
    end)

    self.gateway:on_dispatch("MESSAGE_DELETE_BULK", function(data)
        self:emit("message_delete_bulk", data)
    end)

    self.gateway:on_dispatch("MESSAGE_REACTION_ADD", function(data)
        self:emit("message_reaction_add", data)
    end)

    self.gateway:on_dispatch("MESSAGE_REACTION_REMOVE", function(data)
        self:emit("message_reaction_remove", data)
    end)

    self.gateway:on_dispatch("MESSAGE_REACTION_REMOVE_ALL", function(data)
        self:emit("message_reaction_remove_all", data)
    end)

    self.gateway:on_dispatch("MESSAGE_REACTION_REMOVE_EMOJI", function(data)
        self:emit("message_reaction_remove_emoji", data)
    end)

    self.gateway:on_dispatch("PRESENCE_UPDATE", function(data)
        if data and data.guild_id and data.user and data.user.id then
            local member = self.members:get(data.guild_id, data.user.id)
            local old_member = nil
            if member then
                old_member = {}
                for k, v in pairs(member) do
                    old_member[k] = v
                end
                member.activities = data.activities
                member.status = data.status
                member.client_status = data.client_status
                self.members:put(data.guild_id, member)
            end
            self:emit("presence_update", old_member, data)
            return
        end
        self:emit("presence_update", nil, data)
    end)

    self.gateway:on_dispatch("TYPING_START", function(data)
        if data and data.guild_id and data.member then
            self.members:put(data.guild_id, data.member)
        end
        self:emit("typing_start", data)
    end)

    self.gateway:on_dispatch("GUILD_SCHEDULED_EVENT_CREATE", function(data)
        self:emit("guild_scheduled_event_create", data)
    end)

    self.gateway:on_dispatch("GUILD_SCHEDULED_EVENT_UPDATE", function(data)
        self:emit("guild_scheduled_event_update", data)
    end)

    self.gateway:on_dispatch("GUILD_SCHEDULED_EVENT_DELETE", function(data)
        self:emit("guild_scheduled_event_delete", data)
    end)

    self.gateway:on_dispatch("GUILD_SCHEDULED_EVENT_USER_ADD", function(data)
        self:emit("guild_scheduled_event_user_add", data)
    end)

    self.gateway:on_dispatch("GUILD_SCHEDULED_EVENT_USER_REMOVE", function(data)
        self:emit("guild_scheduled_event_user_remove", data)
    end)

    self.gateway:on_dispatch("INTEGRATION_CREATE", function(data)
        self:emit("integration_create", data)
    end)

    self.gateway:on_dispatch("INTEGRATION_UPDATE", function(data)
        self:emit("integration_update", data)
    end)

    self.gateway:on_dispatch("INTEGRATION_DELETE", function(data)
        self:emit("integration_delete", data)
    end)

    self.gateway:on_dispatch("GUILD_INTEGRATIONS_UPDATE", function(data)
        self:emit("guild_integrations_update", data)
    end)

    self.gateway:on_dispatch("WEBHOOKS_UPDATE", function(data)
        self:emit("webhooks_update", data)
    end)

    self.gateway:on_dispatch("INVITE_CREATE", function(data)
        self:emit("invite_create", data)
    end)

    self.gateway:on_dispatch("INVITE_DELETE", function(data)
        self:emit("invite_delete", data)
    end)

    self.gateway:on_dispatch("INTERACTION_CREATE", function(data)
        self:emit("interaction_create", data)
    end)

    self.gateway:on_dispatch("VOICE_STATE_UPDATE", function(data)
        self.voice_states:update(data)
        self:emit("voice_state_update", data)
    end)

    self.gateway:on_dispatch("VOICE_SERVER_UPDATE", function(data)
        self:emit("voice_server_update", data)
    end)

    self.gateway:on_dispatch("GUILD_CREATE", function(data)
        if data and data.id then
            self.channels:put_many(data.channels, data.id)
            if data.voice_states then
                for _, vs in ipairs(data.voice_states) do
                    vs.guild_id = vs.guild_id or data.id
                    self.voice_states:update(vs)
                end
            end
            if data.members then
                self.members:put_many(data.id, data.members)
            end
            if data.roles then
                self.roles:put_many(data.id, data.roles)
            end
        end
        self:emit("guild_create", data)
    end)

    self.gateway:on_dispatch("GUILD_MEMBER_ADD", function(data)
        if data and data.guild_id then
            self.members:put(data.guild_id, data)
        end
        self:emit("guild_member_add", data)
    end)

    self.gateway:on_dispatch("GUILD_MEMBER_UPDATE", function(data)
        if data and data.guild_id then
            local old_member = self.members:get(data.guild_id, data.user and data.user.id)
            self.members:put(data.guild_id, data)
            self:emit("guild_member_update", old_member, data)
            return
        end
        self:emit("guild_member_update", nil, data)
    end)

    self.gateway:on_dispatch("GUILD_MEMBER_REMOVE", function(data)
        if data and data.guild_id and data.user and data.user.id then
            self.members:remove(data.guild_id, data.user.id)
        end
        self:emit("guild_member_remove", data)
    end)

    self.gateway:on_dispatch("GUILD_MEMBERS_CHUNK", function(data)
        if data and data.guild_id and data.members then
            self.members:put_many(data.guild_id, data.members)
        end
        self:emit("guild_members_chunk", data)
    end)

    self.gateway:on_dispatch("GUILD_ROLE_CREATE", function(data)
        if data and data.guild_id and data.role then
            self.roles:put(data.guild_id, data.role)
        end
        self:emit("guild_role_create", data)
    end)

    self.gateway:on_dispatch("GUILD_ROLE_UPDATE", function(data)
        if data and data.guild_id and data.role then
            local old_role = self.roles:get(data.guild_id, data.role.id)
            self.roles:put(data.guild_id, data.role)
            self:emit("guild_role_update", old_role, data.role)
            return
        end
        self:emit("guild_role_update", nil, data)
    end)

    self.gateway:on_dispatch("GUILD_ROLE_DELETE", function(data)
        if data and data.guild_id and data.role_id then
            self.roles:remove(data.guild_id, data.role_id)
        end
        self:emit("guild_role_delete", data)
    end)

    self.gateway:on_dispatch("GUILD_BAN_ADD", function(data)
        self:emit("guild_ban_add", data)
    end)

    self.gateway:on_dispatch("GUILD_BAN_REMOVE", function(data)
        self:emit("guild_ban_remove", data)
    end)

    self.gateway:on_dispatch("CHANNEL_CREATE", function(data)
        self.channels:put(data)
        self:emit("channel_create", data)
    end)

    self.gateway:on_dispatch("CHANNEL_UPDATE", function(data)
        self.channels:put(data)
        self:emit("channel_update", data)
    end)

    self.gateway:on_dispatch("CHANNEL_DELETE", function(data)
        if data and data.id then
            self.channels:remove(data.id)
        end
        self:emit("channel_delete", data)
    end)

    self.gateway:on_dispatch("THREAD_CREATE", function(data)
        self.channels:put(data)
        self:emit("thread_create", data)
    end)

    self.gateway:on_dispatch("THREAD_UPDATE", function(data)
        if data and data.id then
            local old_thread = self.channels:get(data.id)
            self.channels:put(data)
            self:emit("thread_update", old_thread, data)
            return
        end
        self:emit("thread_update", nil, data)
    end)

    self.gateway:on_dispatch("THREAD_DELETE", function(data)
        if data and data.id then
            self.channels:remove(data.id)
        end
        self:emit("thread_delete", data)
    end)

    self.gateway:on_dispatch("THREAD_LIST_SYNC", function(data)
        if data and data.threads then
            self.channels:put_many(data.threads, data.guild_id)
        end
        self:emit("thread_list_sync", data)
    end)

    self.gateway:on_dispatch("THREAD_MEMBER_UPDATE", function(data)
        self:emit("thread_member_update", data)
    end)

    self.gateway:on_dispatch("THREAD_MEMBERS_UPDATE", function(data)
        self:emit("thread_members_update", data)
    end)

    self.gateway:start()

    return self
end

-- Stop gateway
function Client:stop_gateway()
    if self.gateway then
        self.gateway:stop()
        self.gateway = nil
    end
    return self
end

-- Event methods
function Client:on(event, callback)
    if not self.events[event] then
        self.events[event] = {}
    end
    table.insert(self.events[event], callback)
    return self
end

function Client:once(event, callback)
    local once_fn = function(...)
        callback(...)
        -- luacheck: ignore unused once_fn
        self:off(event, once_fn)
    end
    self:on(event, once_fn)
    return self
end

function Client:emit(event, ...)
    if self.events[event] then
        for _, callback in ipairs(self.events[event]) do
            callback(...)
        end
    end
    return self
end

-- Alias for emit used by voice/lavalink integrations, which fire events
-- like VOICE_CLIENT_CONNECTED using Discord-style upper snake_case names
-- rather than the lower snake_case Client:on() convention.
function Client:dispatch(event, ...)
    return self:emit(event, ...)
end

function Client:off(event, callback)
    if self.events[event] then
        for i, cb in ipairs(self.events[event]) do
            if cb == callback then
                table.remove(self.events[event], i)
                return
            end
        end
    end
    return self
end

-- Gateway-specific event listeners
function Client:on_gateway_ready(callback)
    if not self.listeners.gateway_ready then
        self.listeners.gateway_ready = {}
    end
    table.insert(self.listeners.gateway_ready, callback)
    return self
end

function Client:on_gateway_shard_ready(_shard_id, callback)
    if not self.listeners["gateway_shard_ready"] then
        self.listeners["gateway_shard_ready"] = {}
    end
    table.insert(self.listeners["gateway_shard_ready"], callback)
    return self
end

function Client:on_gateway_shard_error(_shard_id, callback)
    if not self.listeners["gateway_shard_error"] then
        self.listeners["gateway_shard_error"] = {}
    end
    table.insert(self.listeners["gateway_shard_error"], callback)
    return self
end

function Client:on_gateway_shard_disconnect(_shard_id, callback)
    if not self.listeners["gateway_shard_disconnect"] then
        self.listeners["gateway_shard_disconnect"] = {}
    end
    table.insert(self.listeners["gateway_shard_disconnect"], callback)
    return self
end

function Client:on_gateway_event(callback)
    if not self.listeners.gateway_event then
        self.listeners.gateway_event = {}
    end
    table.insert(self.listeners.gateway_event, callback)
    return self
end

-- Getters (these need to be implemented with actual API calls)
function Client:get_user(id)
    if self.rest then
        return self.rest:get_user(id)
    end
    if self.http then
        return self.http:get("/users/" .. id)
    end
    return nil
end

function Client.get_member(_self, _id)
    -- Guild context needed
    return nil
end

function Client:get_channel(id)
    local Channel = require("./channel")

    local data = self.channels:get(id)
    if not data then
        if self.rest then
            data = self.rest:get_channel(id)
        elseif self.http then
            data = self.http:get("/channels/" .. id)
        end
    end
    if not data then
        return nil
    end

    -- Only the guild id is known here (channels are cached as raw
    -- gateway payloads, not full Guild objects), but VoiceClient and
    -- Channel:connect() only ever read channel.guild.id, so a minimal
    -- {id = guild_id} stand-in is enough. Real Guild objects (from
    -- get_guild/GUILD_CREATE) should be preferred where available.
    local guild = data.guild_id and { id = data.guild_id } or nil
    return Channel.new(data, guild, self.http)
end

function Client.get_role(_self, _id)
    -- Guild context needed
    return nil
end

function Client:get_guild(id)
    if self.rest then
        return self.rest:get_guild(id)
    end
    if self.http then
        return self.http:get("/guilds/" .. id)
    end
    return nil
end

-- Gateway event dispatch methods
function Client:dispatch_gateway_event(event)
    -- Dispatch to gateway event listeners
    if self.listeners.gateway_event then
        for _, cb in ipairs(self.listeners.gateway_event) do
            cb(event)
        end
    end
    return self
end

function Client:dispatch_shard_ready(shard_id, shard)
    -- Dispatch to shard ready listeners
    if self.listeners["gateway_shard_ready"] then
        for _, cb in ipairs(self.listeners["gateway_shard_ready"]) do
            cb(shard_id, shard)
        end
    end
    return self
end

function Client:dispatch_shard_error(shard_id, shard, error)
    -- Dispatch to shard error listeners
    if self.listeners["gateway_shard_error"] then
        for _, cb in ipairs(self.listeners["gateway_shard_error"]) do
            cb(shard_id, shard, error)
        end
    end
    return self
end

function Client:dispatch_shard_disconnect(shard_id, shard, event)
    -- Dispatch to shard disconnect listeners
    if self.listeners["gateway_shard_disconnect"] then
        for _, cb in ipairs(self.listeners["gateway_shard_disconnect"]) do
            cb(shard_id, shard, event)
        end
    end
    return self
end

return Client
