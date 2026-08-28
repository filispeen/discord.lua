local class = require("../core/class")
local bitwise = require("../core/bitwise")

local BaseFlags = class("BaseFlags")

function BaseFlags.new(value, definitions, opts)
    if type(value) == "table" and definitions and opts == nil then opts, value = value, 0 end
    local self = { value = tonumber(value) or 0, definitions = definitions or {} }
    setmetatable(self, { __index = BaseFlags })
    for name, enabled in pairs(opts or {}) do self:set(name, enabled) end
    return self
end

function BaseFlags:has(name)
    local flag = type(name) == "string" and self.definitions[name] or name
    if not flag then error("unknown flag", 0) end
    return bitwise.band(self.value, flag) == flag
end

function BaseFlags:set(name, enabled)
    local flag = type(name) == "string" and self.definitions[name] or name
    if not flag then error("unknown flag", 0) end
    self.value = enabled == false and bitwise.band(self.value, bitwise.bnot(flag)) or bitwise.bor(self.value, flag)
    return self
end

function BaseFlags:to_number() return self.value end

function BaseFlags:to_dict()
    local result = {}
    for name, _ in pairs(self.definitions) do result[name] = self:has(name) end
    return result
end

function BaseFlags:equals(other)
    return other and self.value == other.value
end

local function make_type(name, definitions)
    local T = class(name)
    for method, value in pairs(BaseFlags) do T[method] = value end
    function T.new(value, opts)
        local self = BaseFlags.new(value, definitions, opts)
        setmetatable(self, { __index = T })
        return self
    end
    function T.all()
        local value = 0
        for _, flag in pairs(definitions) do value = bitwise.bor(value, flag) end
        return T.new(value)
    end
    T.DEFINITIONS = definitions
    return T
end

return {
    BaseFlags = BaseFlags,
    SystemChannelFlags = make_type("SystemChannelFlags", {
        join_notifications = 1, premium_subscriptions = 2,
        guild_reminder_notifications = 4, join_notification_replies = 8,
        role_subscription_purchase_notifications = 16,
        role_subscription_purchase_notification_replies = 32,
    }),
    MessageFlags = make_type("MessageFlags", {
        crossposted = 1, is_crossposted = 2, suppress_embeds = 4,
        source_message_deleted = 8, urgent = 16, has_thread = 32,
        ephemeral = 64, loading = 128, failed_to_mention_some_roles_in_thread = 256,
        suppress_notifications = 4096, is_voice_message = 8192,
        is_components_v2 = 32768, has_snapshot = 16384,
    }),
    PublicUserFlags = make_type("PublicUserFlags", {
        staff = 1, partner = 2, hypesquad = 4, bug_hunter = 8,
        hypesquad_bravery = 64, hypesquad_brilliance = 128, hypesquad_balance = 256,
        early_supporter = 512, team_user = 1024, system = 4096,
        bug_hunter_level_2 = 16384, verified_bot = 65536,
        verified_bot_developer = 131072, discord_certified_moderator = 262144,
        bot_http_interactions = 524288, active_developer = 4194304,
    }),
    ApplicationFlags = make_type("ApplicationFlags", {
        managed_emoji = 4, group_dm_create = 16,
        application_auto_moderation_rule_create_badge = 64, rpc_has_connected = 2048,
        gateway_presence = 4096, gateway_presence_limited = 8192,
        gateway_guild_members = 16384, gateway_guild_members_limited = 32768,
        verification_pending_guild_limit = 65536, embedded = 131072,
        gateway_message_content = 262144, gateway_message_content_limited = 524288,
        app_commands_badge = 8388608, active = 16777216,
    }),
    ChannelFlags = make_type("ChannelFlags", {
        pinned = 2, require_tag = 16, hide_media_download_options = 32768, obfuscated = 65536,
    }),
    SKUFlags = make_type("SKUFlags", {
        available = 4, guild_subscription = 128, user_subscription = 256,
    }),
    MemberFlags = make_type("MemberFlags", {
        did_rejoin = 1, completed_onboarding = 2, bypasses_verification = 4, started_onboarding = 8,
    }),
    RoleFlags = make_type("RoleFlags", { in_prompt = 1 }),
}
