-- lib/models/client.lua
-- Main client model for Discord.lua
--
-- Public Contract:
--   Client.new(token, ratelimiter, intents?, opts?) -> Client
--     Creates a new Discord client. opts.status/opts.activity set the
--     initial presence sent with IDENTIFY (see Shard:dispatch's HELLO
--     handling); opts.activity must be a Game/Streaming/Activity/
--     CustomActivity instance from lib/models/activity.lua. Use
--     Client:change_presence to update presence after connecting.
--
--   Client:change_presence(opts) -> boolean, string?
--     Updates the live presence (status/activity) through the gateway,
--     see the method's own doc comment below for opts fields.
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

function Client.new(token, ratelimiter, intents, opts)
    local enums = require("../core/enums")
    local VoiceStateStore = require("../cache/voice_state_store")
    local ChannelStore = require("../cache/channel_store")
    local MemberStore = require("../cache/member_store")
    local RoleStore = require("../cache/role_store")
    local MessageStore = require("../cache/message_store")
    opts = opts or {}

    if opts.activity ~= nil and type(opts.activity.to_dict) ~= "function" then
        error("Client.new opts.activity must be a BaseActivity (Game/Streaming/Activity/CustomActivity) with a to_dict method", 0)
    end

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
        messages = MessageStore.new(),
        automod_rules = {},
        stage_instances = {},
        soundboard_sounds = {},
        -- Initial presence sent with IDENTIFY, see Shard:dispatch's HELLO
        -- handling. Client:change_presence updates presence live once
        -- the gateway is already connected instead.
        _initial_status = opts.status,
        _initial_activity = opts.activity,
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

-- Fetches a guild Template from a discord.new URL or a bare code,
-- mirrors pycord's Client.fetch_template(). code is accepted either
-- as a plain code or a full "https://discord.new/{code}" (or
-- "discord.gg/{code}", matching pycord's resolve_template regex,
-- which is shared with resolve_invite) URL -- the discord.new/ prefix
-- is stripped via the same pattern pycord's utils.resolve_template
-- uses, otherwise the string is used as-is.
function Client:fetch_template(code)
    if not self.http then
        error("Client:fetch_template called with no http client attached", 0)
    end
    if not code then
        error("Client:fetch_template requires a code", 0)
    end

    local resolved = code:match("^https?://discord%.new/(.+)$")
        or code:match("^discord%.new/(.+)$")
        or code

    local Route = require("../http/route")
    local Template = require("./template")
    local route = Route.new(self.http)

    local data = route:get_template(resolved)
    return Template.new(data, self.http)
end

-- Fetches a guild Widget by guild_id, mirrors pycord's
-- Client.fetch_widget(). Same Client-level HTTP-fetch style as
-- Client:fetch_template above -- a widget is fetched by guild_id
-- directly, no guild instance required (the widget.json endpoint is
-- public and needs no auth, but this project's http client always
-- signs requests the same way regardless, same as get_invite).
function Client:fetch_widget(guild_id)
    if not self.http then
        error("Client:fetch_widget called with no http client attached", 0)
    end
    if not guild_id then
        error("Client:fetch_widget requires a guild_id", 0)
    end

    local Route = require("../http/route")
    local WidgetModule = require("./widget")
    local route = Route.new(self.http)

    local data = route:get_widget(guild_id)
    return WidgetModule.Widget.new(data, self.http)
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

-- Changes the client's live presence (status + activity), mirrors
-- pycord's Client.change_presence / AutoShardedClient.change_presence.
-- opts.status: status string ("online"/"idle"/"dnd"/"invisible"/
--   "offline"), defaults to "online" when nil. "offline" is remapped
--   to the wire value "invisible" same as pycord's Status.offline ->
--   "invisible" (Discord's gateway only accepts "invisible" from
--   clients, "offline" is only ever a received/displayed value).
-- opts.activity: a Game/Streaming/Activity/CustomActivity instance
--   (see lib/models/activity.lua), or nil to clear the current
--   activity.
-- opts.shard_id: update only that shard's presence instead of every
--   shard the gateway manages (same shard_id parameter pycord's
--   AutoShardedClient.change_presence exposes).
-- Requires the gateway to already be started (Client:start_gateway /
-- Bot:run), same requirement as Client:voice_state_update. For the
-- presence a bot connects with initially, pass opts.status/opts.activity
-- to Client.new instead (sent as part of IDENTIFY, see shard.lua).
function Client:change_presence(opts)
    opts = opts or {}
    if not self.gateway then
        error("Client:change_presence called before start_gateway()", 0)
    end

    local status = opts.status
    if status == nil then
        status = "online"
    elseif status == "offline" then
        status = "invisible"
    end

    return self.gateway:change_presence(status, opts.activity, opts.shard_id)
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

function Client:get_cached_message(channel_id, message_id)
    return self.messages:get(channel_id, message_id)
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
        local message = Message.new(data, self.http)
        self.messages:put(message)
        self:emit("message_create", message)
    end)

    self.gateway:on_dispatch("MESSAGE_UPDATE", function(data)
        local message = data and self.messages:get(data.channel_id, data.id)
        if message then
            local old_message = message:_copy()
            message:_update(data)
            self:emit("message_update", old_message, message)
            return
        end
        local Message = require("./message")
        local new_message = Message.new(data, self.http)
        self.messages:put(new_message)
        self:emit("message_update", nil, new_message)
    end)

    self.gateway:on_dispatch("MESSAGE_DELETE", function(data)
        if data then
            self.messages:remove(data.channel_id, data.id)
        end
        self:emit("message_delete", data)
    end)

    self.gateway:on_dispatch("MESSAGE_DELETE_BULK", function(data)
        if data then
            self.messages:remove_many(data.channel_id, data.ids)
        end
        self:emit("message_delete_bulk", data)
    end)

    self.gateway:on_dispatch("MESSAGE_REACTION_ADD", function(data)
        local message = data and self.messages:get(data.channel_id, data.message_id)
        if message then
            message:_add_reaction(data, self.user and self.user.id)
        end
        self:emit("message_reaction_add", data)
    end)

    self.gateway:on_dispatch("MESSAGE_REACTION_REMOVE", function(data)
        local message = data and self.messages:get(data.channel_id, data.message_id)
        if message then
            message:_remove_reaction(data, self.user and self.user.id)
        end
        self:emit("message_reaction_remove", data)
    end)

    self.gateway:on_dispatch("MESSAGE_REACTION_REMOVE_ALL", function(data)
        local message = data and self.messages:get(data.channel_id, data.message_id)
        if message then
            message:_clear_reactions()
        end
        self:emit("message_reaction_remove_all", data)
    end)

    self.gateway:on_dispatch("MESSAGE_REACTION_REMOVE_EMOJI", function(data)
        local message = data and self.messages:get(data.channel_id, data.message_id)
        if message then
            message:_clear_emoji(data.emoji)
        end
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

    self.gateway:on_dispatch("GUILD_UPDATE", function(data)
        self:emit("guild_update", data)
    end)

    self.gateway:on_dispatch("GUILD_DELETE", function(data)
        if data and data.id then
            self.channels:remove_guild(data.id)
            self.members:remove_guild(data.id)
            self.roles:remove_guild(data.id)
            self.voice_states:remove_guild(data.id)
            self.automod_rules[data.id] = nil
            self.stage_instances[data.id] = nil
            self.soundboard_sounds[data.id] = nil
        end
        self:emit("guild_delete", data)
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

    self.gateway:on_dispatch("CHANNEL_PINS_UPDATE", function(data)
        self:emit("channel_pins_update", data)
    end)

    self.gateway:on_dispatch("GUILD_EMOJIS_UPDATE", function(data)
        self:emit("guild_emojis_update", data)
    end)

    self.gateway:on_dispatch("GUILD_STICKERS_UPDATE", function(data)
        self:emit("guild_stickers_update", data)
    end)

    self.gateway:on_dispatch("AUTO_MODERATION_RULE_CREATE", function(data)
        local AutoModRule = require("./automod").AutoModRule
        local rule = AutoModRule.new(data, nil, self.http)
        if rule.guild_id and rule.id then
            self.automod_rules[rule.guild_id] = self.automod_rules[rule.guild_id] or {}
            self.automod_rules[rule.guild_id][rule.id] = rule
        end
        self:emit("automod_rule_create", rule)
    end)

    self.gateway:on_dispatch("AUTO_MODERATION_RULE_UPDATE", function(data)
        local AutoModRule = require("./automod").AutoModRule
        local old_rule = data and data.guild_id and data.id and self.automod_rules[data.guild_id]
            and self.automod_rules[data.guild_id][data.id] or nil
        local rule = AutoModRule.new(data, nil, self.http)
        if rule.guild_id and rule.id then
            self.automod_rules[rule.guild_id] = self.automod_rules[rule.guild_id] or {}
            self.automod_rules[rule.guild_id][rule.id] = rule
        end
        self:emit("automod_rule_update", old_rule, rule)
    end)

    self.gateway:on_dispatch("AUTO_MODERATION_RULE_DELETE", function(data)
        local AutoModRule = require("./automod").AutoModRule
        local rule = data and data.guild_id and data.id and self.automod_rules[data.guild_id]
            and self.automod_rules[data.guild_id][data.id] or AutoModRule.new(data, nil, self.http)
        if data and data.guild_id and data.id and self.automod_rules[data.guild_id] then
            self.automod_rules[data.guild_id][data.id] = nil
        end
        self:emit("automod_rule_delete", rule)
    end)

    self.gateway:on_dispatch("AUTO_MODERATION_ACTION_EXECUTION", function(data)
        self:emit("automod_action_execution", data)
    end)

    self.gateway:on_dispatch("MESSAGE_POLL_VOTE_ADD", function(data)
        local message = data and self.messages:get(data.channel_id, data.message_id)
        if message and message.poll then
            message.poll:_add_vote(data.answer_id, data.user_id, self.user and self.user.id)
        end
        self:emit("message_poll_vote_add", data)
    end)

    self.gateway:on_dispatch("MESSAGE_POLL_VOTE_REMOVE", function(data)
        local message = data and self.messages:get(data.channel_id, data.message_id)
        if message and message.poll then
            message.poll:_remove_vote(data.answer_id, data.user_id, self.user and self.user.id)
        end
        self:emit("message_poll_vote_remove", data)
    end)

    self.gateway:on_dispatch("STAGE_INSTANCE_CREATE", function(data)
        local StageInstance = require("./stage_instance")
        local instance = StageInstance.new(data, nil, self.http)
        if instance.guild_id and instance.id then
            self.stage_instances[instance.guild_id] = self.stage_instances[instance.guild_id] or {}
            self.stage_instances[instance.guild_id][instance.id] = instance
        end
        self:emit("stage_instance_create", instance)
    end)

    self.gateway:on_dispatch("STAGE_INSTANCE_UPDATE", function(data)
        local StageInstance = require("./stage_instance")
        local old_instance = data and data.guild_id and data.id and self.stage_instances[data.guild_id]
            and self.stage_instances[data.guild_id][data.id] or nil
        local instance = StageInstance.new(data, nil, self.http)
        if instance.guild_id and instance.id then
            self.stage_instances[instance.guild_id] = self.stage_instances[instance.guild_id] or {}
            self.stage_instances[instance.guild_id][instance.id] = instance
        end
        self:emit("stage_instance_update", old_instance, instance)
    end)

    self.gateway:on_dispatch("STAGE_INSTANCE_DELETE", function(data)
        local StageInstance = require("./stage_instance")
        local instance = data and data.guild_id and data.id and self.stage_instances[data.guild_id]
            and self.stage_instances[data.guild_id][data.id] or StageInstance.new(data, nil, self.http)
        if data and data.guild_id and data.id and self.stage_instances[data.guild_id] then
            self.stage_instances[data.guild_id][data.id] = nil
        end
        self:emit("stage_instance_delete", instance)
    end)

    self.gateway:on_dispatch("GUILD_SOUNDBOARD_SOUND_CREATE", function(data)
        local Sound = require("./sound")
        local sound = Sound.new(data, data and data.guild_id, self.http)
        if sound.guild_id and sound.id then
            self.soundboard_sounds[sound.guild_id] = self.soundboard_sounds[sound.guild_id] or {}
            self.soundboard_sounds[sound.guild_id][sound.id] = sound
        end
        self:emit("guild_soundboard_sound_create", sound)
    end)

    self.gateway:on_dispatch("GUILD_SOUNDBOARD_SOUND_UPDATE", function(data)
        local Sound = require("./sound")
        local old_sound = data and data.guild_id and (data.sound_id or data.id) and self.soundboard_sounds[data.guild_id]
            and self.soundboard_sounds[data.guild_id][data.sound_id or data.id] or nil
        local sound = Sound.new(data, data and data.guild_id, self.http)
        if sound.guild_id and sound.id then
            self.soundboard_sounds[sound.guild_id] = self.soundboard_sounds[sound.guild_id] or {}
            self.soundboard_sounds[sound.guild_id][sound.id] = sound
        end
        self:emit("guild_soundboard_sound_update", old_sound, sound)
    end)

    self.gateway:on_dispatch("GUILD_SOUNDBOARD_SOUND_DELETE", function(data)
        local Sound = require("./sound")
        local sound_id = data and (data.sound_id or data.id)
        local sound = data and data.guild_id and sound_id and self.soundboard_sounds[data.guild_id]
            and self.soundboard_sounds[data.guild_id][sound_id] or Sound.new(data, data and data.guild_id, self.http)
        if data and data.guild_id and sound_id and self.soundboard_sounds[data.guild_id] then
            self.soundboard_sounds[data.guild_id][sound_id] = nil
        end
        self:emit("guild_soundboard_sound_delete", sound)
    end)

    self.gateway:on_dispatch("GUILD_SOUNDBOARD_SOUNDS_UPDATE", function(data)
        local Sound = require("./sound")
        if data and data.guild_id then
            local sounds = {}
            for _, sound_data in ipairs(data.soundboard_sounds or {}) do
                local sound = Sound.new(sound_data, data.guild_id, self.http)
                sounds[sound.id] = sound
            end
            self.soundboard_sounds[data.guild_id] = sounds
        end
        self:emit("guild_soundboard_sounds_update", data)
    end)

    self.gateway:on_dispatch("GUILD_AUDIT_LOG_ENTRY_CREATE", function(data)
        local AuditLogEntry = require("./audit_log").AuditLogEntry
        self:emit("audit_log_entry_create", AuditLogEntry.new(data, nil, self.http))
    end)

    self.gateway:on_dispatch("ENTITLEMENT_CREATE", function(data)
        self:emit("entitlement_create", data)
    end)

    self.gateway:on_dispatch("ENTITLEMENT_UPDATE", function(data)
        self:emit("entitlement_update", data)
    end)

    self.gateway:on_dispatch("ENTITLEMENT_DELETE", function(data)
        self:emit("entitlement_delete", data)
    end)

    self.gateway:on_dispatch("SUBSCRIPTION_CREATE", function(data)
        self:emit("subscription_create", data)
    end)

    self.gateway:on_dispatch("SUBSCRIPTION_UPDATE", function(data)
        self:emit("subscription_update", data)
    end)

    self.gateway:on_dispatch("SUBSCRIPTION_DELETE", function(data)
        self:emit("subscription_delete", data)
    end)

    self.gateway:on_dispatch("USER_UPDATE", function(data)
        local User = require("./user")
        local old_user = self.user
        local user = User.new(data)
        self.user = user
        self:emit("user_update", old_user, user)
    end)

    self.gateway:on_dispatch("VOICE_CHANNEL_EFFECT_SEND", function(data)
        self:emit("voice_channel_effect_send", data)
    end)

    self.gateway:on_dispatch("VOICE_CHANNEL_STATUS_UPDATE", function(data)
        self:emit("voice_channel_status_update", data)
    end)

    self.gateway:on_dispatch("APPLICATION_COMMAND_PERMISSIONS_UPDATE", function(data)
        self:emit("application_command_permissions_update", data)
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
