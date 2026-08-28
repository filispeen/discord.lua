-- lib/models/guild.lua
-- Guild model for Discord API
--
-- Public Contract:
--   Guild.new(data, http) -> Guild
--     Creates a new Guild from API data. http is optional, an http.client
--     instance used by Guild:fetch_sounds/:create_sound.
--
--   Guild:id -> string
--     Guild's unique ID.
--
--   Guild:name -> string
--     Guild name.
--
--   Guild:icon -> string or nil
--     Guild icon hash (or nil if no icon).
--
--   Guild:owner_id -> string
--     Guild owner's user ID.
--
--   Guild:roles -> table
--     Guild roles.
--
--   Guild:emojis -> table
--     Guild emojis.
--
--   Guild:channels -> table
--     Guild channels.
--
--   Guild:member_count -> number
--     Number of guild members.
--
--   Guild:features -> table
--     Guild features.
--
--   Guild:verification_level -> number
--     Guild verification level.
--
--   Guild:vanity_url_code -> string or nil
--     Vanity URL code.
--
--   Guild:premium_subscription_level -> number
--     Premium subscription level.
--
--   Guild:nsfw -> boolean
--     True if guild is NSFW.
--
--   guild:fetch_sounds() -> table of Sound
--     GET /guilds/{guild_id}/soundboard-sounds, mirrors pycord's
--     Guild.fetch_sounds().
--
--   guild:create_sound(opts) -> Sound
--     opts.name: string, required
--     opts.sound: string - base64-encoded audio data URI (data:audio/...;base64,...)
--     opts.volume: number or nil - defaults to 1.0
--     opts.emoji_id / opts.emoji_name: optional, mutually exclusive
--     POST /guilds/{guild_id}/soundboard-sounds, mirrors pycord's
--     Guild.create_sound().
--
--   guild:fetch_scheduled_events(with_user_count?) -> table of ScheduledEvent
--     GET /guilds/{guild_id}/scheduled-events, mirrors pycord's
--     Guild.fetch_scheduled_events(). with_user_count defaults to true.
--
--   guild:fetch_scheduled_event(event_id, with_user_count?) -> ScheduledEvent
--     GET /guilds/{guild_id}/scheduled-events/{event_id}, mirrors
--     pycord's Guild.fetch_scheduled_event(). with_user_count defaults
--     to true.
--
--   guild:create_scheduled_event(opts) -> ScheduledEvent
--     opts.name (required), opts.start_time (required, ISO 8601),
--     opts.end_time, opts.description, opts.privacy_level (default 2 =
--     guild_only), opts.reason, plus exactly one of:
--       opts.channel_id (+ opts.entity_type, default 2 = voice)
--       opts.location (sets entity_type=external + entity_metadata)
--     POST /guilds/{guild_id}/scheduled-events, mirrors pycord's
--     Guild.create_scheduled_event().
--
--   guild:fetch_automod_rules() -> table of AutoModRule
--     GET /guilds/{guild_id}/auto-moderation/rules, mirrors pycord's
--     Guild.fetch_auto_moderation_rules().
--
--   guild:fetch_automod_rule(rule_id) -> AutoModRule
--     GET /guilds/{guild_id}/auto-moderation/rules/{rule_id}, mirrors
--     pycord's Guild.fetch_auto_moderation_rule().
--
--   guild:create_automod_rule(opts) -> AutoModRule
--     opts.name (required), opts.event_type (required, default 1 =
--     message_send), opts.trigger_type (required),
--     opts.trigger_metadata (AutoModTriggerMetadata, optional),
--     opts.actions (required, array of AutoModAction), opts.enabled
--     (default false), opts.exempt_role_ids, opts.exempt_channel_ids,
--     opts.reason. POST /guilds/{guild_id}/auto-moderation/rules,
--     mirrors pycord's Guild.create_auto_moderation_rule().
--
--   guild:fetch_audit_logs(opts?) -> table of AuditLogEntry
--     GET /guilds/{guild_id}/audit-logs, mirrors pycord's
--     Guild.audit_logs() (a paginated async iterator there; here just a
--     single page). opts.limit (default 100), opts.before, opts.after,
--     opts.user_id, opts.action_type all optional and map directly to
--     the endpoint's query parameters. Returns only the
--     audit_log_entries array wrapped as AuditLogEntry instances --
--     the response envelope's users/threads/webhooks/integrations/
--     guild_scheduled_events/application_commands side-load arrays are
--     not exposed, since AuditLogEntry itself does not resolve ids into
--     model instances (see lib/models/audit_log.lua for why).
--
--   guild:fetch_integrations() -> table of Integration/StreamIntegration/BotIntegration
--     GET /guilds/{guild_id}/integrations, mirrors pycord's
--     Guild.integrations(). Picks the concrete class per entry's "type"
--     field the same way pycord's _integration_factory does (see
--     lib/models/integration.lua's from_data).
--
--   guild:fetch_templates() -> table of Template
--     GET /guilds/{guild_id}/templates, mirrors pycord's
--     Guild.templates().
--   guild:create_template(opts) -> Template
--     POST /guilds/{guild_id}/templates. opts.name (required),
--     opts.description (optional), mirrors pycord's
--     Guild.create_template().
--
--   guild:welcome_screen() -> WelcomeScreen
--     GET /guilds/{guild_id}/welcome-screen, mirrors pycord's
--     Guild.welcome_screen().
--
--   guild:edit_welcome_screen(opts) -> WelcomeScreen
--     Shorthand for WelcomeScreen:edit without fetching first, mirrors
--     pycord's Guild.edit_welcome_screen(). opts.description /
--     opts.welcome_channels / opts.enabled / opts.reason, all
--     optional -- see lib/models/welcome_screen.lua.
--
--   guild:widget() -> Widget
--     GET /guilds/{guild_id}/widget.json, mirrors pycord's
--     Guild.widget().
--
--   guild:edit_widget(opts) -> nil
--     PATCH /guilds/{guild_id}/widget, mirrors pycord's
--     Guild.edit_widget(enabled=..., channel=...). opts.enabled /
--     opts.channel_id, both optional. opts.clear_channel = true sends
--     an explicit JSON null for channel_id (clears the widget
--     channel) -- see lib/models/widget.lua.

local class = require("../core/class")

-- Guild class
local Guild = class("Guild")

function Guild.new(data, http)
    local self = {}
    setmetatable(self, {
        __index = Guild
    })

    self.id = data.id
    self.name = data.name
    self.icon = data.icon
    self.icon_asset = data.icon and require("./asset").from_guild_icon(data.id, data.icon) or nil
    self.owner_id = data.owner_id
    self.roles = data.roles or {}
    self.emojis = data.emojis or {}
    self.channels = data.channels or {}
    self.member_count = data.member_count or 0
    self.features = data.features or {}
    self.verification_level = data.verification_level or 1
    self.vanity_url_code = data.vanity_url_code
    self.premium_subscription_level = data.premium_subscription_level or 0
    self.nsfw = data.nsfw or false

    -- Additional fields
    self.afk_channel_id = data.afk_channel_id or nil
    self.afk_timeout = data.afk_timeout or 300
    self.region = data.region or "us-west"
    self.joined_at = data.joined_at or nil
    self.large = data.large or false
    self.unavailable = data.unavailable or false
    self.splash = data.splash or nil
    self.discovery_splash = data.discovery_splash or nil
    self.description = data.description or nil
    self.bans = data.bans or {}
    self.threads = data.threads or {}
    self.webhooks = data.webhooks or {}
    self.stickers = data.stickers or {}
    self.explicit_content_filter = data.explicit_content_filter or 0
    self.mfa_level = data.mfa_level or 1

    self.http = http

    return self
end

function Guild:fetch_sounds()
    if not self.http then
        error("Guild has no http client attached, cannot fetch sounds", 0)
    end

    local Route = require("../http/route")
    local Sound = require("./sound")
    local route = Route.new(self.http)
    local response = route:get_guild_sounds(self.id)

    local items = response and response.items or response or {}
    local sounds = {}
    for i, sound_data in ipairs(items) do
        sounds[i] = Sound.new(sound_data, self.id, self.http)
    end
    return sounds
end

function Guild:create_sound(opts)
    opts = opts or {}
    if not self.http then
        error("Guild has no http client attached, cannot create a sound", 0)
    end
    if not opts.name then
        error("Guild:create_sound requires opts.name", 0)
    end
    if not opts.sound then
        error("Guild:create_sound requires opts.sound", 0)
    end

    local Route = require("../http/route")
    local Sound = require("./sound")
    local route = Route.new(self.http)

    local payload = {
        name = opts.name,
        sound = opts.sound,
        volume = opts.volume or 1.0,
        emoji_id = opts.emoji_id,
        emoji_name = opts.emoji_name,
    }

    local created = route:create_guild_sound(self.id, payload, opts.reason)
    return Sound.new(created, self.id, self.http)
end

function Guild:fetch_scheduled_events(with_user_count)
    if not self.http then
        error("Guild has no http client attached, cannot fetch scheduled events", 0)
    end
    if with_user_count == nil then
        with_user_count = true
    end

    local Route = require("../http/route")
    local ScheduledEvent = require("./scheduled_event")
    local route = Route.new(self.http)

    local raw_events = route:get_guild_scheduled_events(self.id, with_user_count)
    local events = {}
    for i, event_data in ipairs(raw_events or {}) do
        events[i] = ScheduledEvent.new(event_data, self, self.http)
    end
    return events
end

function Guild:fetch_scheduled_event(event_id, with_user_count)
    if not self.http then
        error("Guild has no http client attached, cannot fetch a scheduled event", 0)
    end
    if with_user_count == nil then
        with_user_count = true
    end

    local Route = require("../http/route")
    local ScheduledEvent = require("./scheduled_event")
    local route = Route.new(self.http)

    local event_data = route:get_guild_scheduled_event(self.id, event_id, with_user_count)
    return ScheduledEvent.new(event_data, self, self.http)
end

function Guild:create_scheduled_event(opts)
    opts = opts or {}
    if not self.http then
        error("Guild has no http client attached, cannot create a scheduled event", 0)
    end
    if not opts.name then
        error("Guild:create_scheduled_event requires opts.name", 0)
    end
    if not opts.start_time then
        error("Guild:create_scheduled_event requires opts.start_time", 0)
    end
    if not opts.channel_id and not opts.location then
        error("Guild:create_scheduled_event requires opts.channel_id or opts.location", 0)
    end

    local Route = require("../http/route")
    local ScheduledEvent = require("./scheduled_event")
    local route = Route.new(self.http)

    local payload = {
        name = opts.name,
        scheduled_start_time = opts.start_time,
        scheduled_end_time = opts.end_time,
        description = opts.description,
        privacy_level = opts.privacy_level or 2,
    }

    if opts.location then
        payload.entity_type = 3
        payload.entity_metadata = { location = opts.location }
    else
        payload.channel_id = opts.channel_id
        payload.entity_type = opts.entity_type or 2
    end

    local created = route:create_guild_scheduled_event(self.id, payload, opts.reason)
    return ScheduledEvent.new(created, self, self.http)
end

function Guild:fetch_automod_rules()
    if not self.http then
        error("Guild has no http client attached, cannot fetch automod rules", 0)
    end

    local Route = require("../http/route")
    local AutoMod = require("./automod")
    local route = Route.new(self.http)

    local raw_rules = route:get_auto_moderation_rules(self.id)
    local rules = {}
    for i, rule_data in ipairs(raw_rules or {}) do
        rules[i] = AutoMod.AutoModRule.new(rule_data, self, self.http)
    end
    return rules
end

function Guild:fetch_automod_rule(rule_id)
    if not self.http then
        error("Guild has no http client attached, cannot fetch an automod rule", 0)
    end

    local Route = require("../http/route")
    local AutoMod = require("./automod")
    local route = Route.new(self.http)

    local rule_data = route:get_auto_moderation_rule(self.id, rule_id)
    return AutoMod.AutoModRule.new(rule_data, self, self.http)
end

function Guild:create_automod_rule(opts)
    opts = opts or {}
    if not self.http then
        error("Guild has no http client attached, cannot create an automod rule", 0)
    end
    if not opts.name then
        error("Guild:create_automod_rule requires opts.name", 0)
    end
    if not opts.trigger_type then
        error("Guild:create_automod_rule requires opts.trigger_type", 0)
    end
    if not opts.actions then
        error("Guild:create_automod_rule requires opts.actions", 0)
    end

    local Route = require("../http/route")
    local AutoMod = require("./automod")
    local route = Route.new(self.http)

    local actions = {}
    for i, action in ipairs(opts.actions) do
        actions[i] = action:to_dict()
    end

    local payload = {
        name = opts.name,
        event_type = opts.event_type or 1,
        trigger_type = opts.trigger_type,
        actions = actions,
        enabled = opts.enabled or false,
        exempt_roles = opts.exempt_role_ids,
        exempt_channels = opts.exempt_channel_ids,
    }
    if opts.trigger_metadata then
        payload.trigger_metadata = opts.trigger_metadata:to_dict()
    end

    local created = route:create_auto_moderation_rule(self.id, payload, opts.reason)
    return AutoMod.AutoModRule.new(created, self, self.http)
end

function Guild:fetch_audit_logs(opts)
    opts = opts or {}
    if not self.http then
        error("Guild has no http client attached, cannot fetch audit logs", 0)
    end

    local Route = require("../http/route")
    local AuditLog = require("./audit_log")
    local route = Route.new(self.http)

    local params = { limit = opts.limit or 100 }
    if opts.before ~= nil then
        params.before = opts.before
    end
    if opts.after ~= nil then
        params.after = opts.after
    end
    if opts.user_id ~= nil then
        params.user_id = opts.user_id
    end
    if opts.action_type ~= nil then
        params.action_type = opts.action_type
    end

    local response = route:get_audit_logs(self.id, params)
    local entries = {}
    for i, entry_data in ipairs((response and response.audit_log_entries) or {}) do
        entries[i] = AuditLog.AuditLogEntry.new(entry_data, self, self.http)
    end
    return entries
end

function Guild:fetch_integrations()
    if not self.http then
        error("Guild has no http client attached, cannot fetch integrations", 0)
    end

    local Route = require("../http/route")
    local Integration = require("./integration")
    local route = Route.new(self.http)

    local raw_integrations = route:get_all_integrations(self.id)
    local integrations = {}
    for i, integration_data in ipairs(raw_integrations or {}) do
        integrations[i] = Integration.from_data(integration_data, self, self.http)
    end
    return integrations
end

function Guild:fetch_templates()
    if not self.http then
        error("Guild has no http client attached, cannot fetch templates", 0)
    end

    local Route = require("../http/route")
    local Template = require("./template")
    local route = Route.new(self.http)

    local raw_templates = route:get_guild_templates(self.id)
    local templates = {}
    for i, template_data in ipairs(raw_templates or {}) do
        templates[i] = Template.new(template_data, self.http)
    end
    return templates
end

function Guild:create_template(opts)
    opts = opts or {}
    if not self.http then
        error("Guild has no http client attached, cannot create_template", 0)
    end
    if not opts.name then
        error("Guild:create_template() requires opts.name", 0)
    end

    local Route = require("../http/route")
    local Template = require("./template")
    local route = Route.new(self.http)

    local payload = { name = opts.name }
    if opts.description then
        payload.description = opts.description
    end

    local data = route:create_template(self.id, payload)
    return Template.new(data, self.http)
end

function Guild:welcome_screen()
    if not self.http then
        error("Guild has no http client attached, cannot fetch welcome screen", 0)
    end

    local Route = require("../http/route")
    local WelcomeScreenModule = require("./welcome_screen")
    local route = Route.new(self.http)

    local data = route:get_welcome_screen(self.id)
    return WelcomeScreenModule.WelcomeScreen.new(data, self, self.http)
end

function Guild:edit_welcome_screen(opts)
    opts = opts or {}
    if not self.http then
        error("Guild has no http client attached, cannot edit welcome screen", 0)
    end

    local WelcomeScreenModule = require("./welcome_screen")
    local screen = WelcomeScreenModule.WelcomeScreen.new({}, self, self.http)
    return screen:edit(opts)
end

function Guild:widget()
    if not self.http then
        error("Guild has no http client attached, cannot fetch widget", 0)
    end

    local Route = require("../http/route")
    local WidgetModule = require("./widget")
    local route = Route.new(self.http)

    local data = route:get_widget(self.id)
    return WidgetModule.Widget.new(data, self.http)
end

function Guild:edit_widget(opts)
    opts = opts or {}
    if not self.http then
        error("Guild has no http client attached, cannot edit widget", 0)
    end

    local Route = require("../http/route")
    local route = Route.new(self.http)

    local payload = {}
    if opts.clear_channel then
        local json = require("../core/json_compat")
        payload.channel_id = json.null
    elseif opts.channel_id ~= nil then
        payload.channel_id = opts.channel_id
    end
    if opts.enabled ~= nil then
        payload.enabled = opts.enabled
    end

    route:edit_widget(self.id, payload)
    return nil
end

function Guild:fetch_emojis()
    if not self.http then error("Guild has no http client attached, cannot fetch emojis", 0) end
    local Route = require("../http/route")
    local Emoji = require("./emoji")
    local data = Route.new(self.http):get_guild_emojis(self.id)
    local result = {}
    for i, item in ipairs(data or {}) do result[i] = Emoji.new(item, self, self.http) end
    self.emojis = result
    return result
end

function Guild:create_emoji(opts)
    opts = opts or {}
    if not self.http then error("Guild has no http client attached, cannot create emoji", 0) end
    if not opts.name or not opts.image then error("Guild:create_emoji requires opts.name and opts.image", 0) end
    local Route = require("../http/route")
    local Emoji = require("./emoji")
    local data = Route.new(self.http):create_guild_emoji(self.id, { name = opts.name, image = opts.image, roles = opts.roles }, opts.reason)
    return Emoji.new(data, self, self.http)
end

function Guild:fetch_stickers()
    if not self.http then error("Guild has no http client attached, cannot fetch stickers", 0) end
    local Route = require("../http/route")
    local Sticker = require("./sticker")
    local data = Route.new(self.http):get_guild_stickers(self.id)
    local result = {}
    for i, item in ipairs(data or {}) do result[i] = Sticker.new(item, self, self.http) end
    self.stickers = result
    return result
end

function Guild:fetch_sticker(sticker_id)
    if not self.http then error("Guild has no http client attached, cannot fetch sticker", 0) end
    local Route = require("../http/route")
    local Sticker = require("./sticker")
    return Sticker.new(Route.new(self.http):get_guild_sticker(self.id, sticker_id), self, self.http)
end

function Guild:create_sticker(opts)
    opts = opts or {}
    if not self.http then error("Guild has no http client attached, cannot create sticker", 0) end
    if not opts.name or not opts.description or not opts.tags or not opts.file then error("Guild:create_sticker requires opts.name, opts.description, opts.tags and opts.file", 0) end
    local Route = require("../http/route")
    local Sticker = require("./sticker")
    local data = Route.new(self.http):create_guild_sticker(self.id, { name = opts.name, description = opts.description, tags = opts.tags }, { opts.file }, opts.reason)
    return Sticker.new(data, self, self.http)
end

function Guild:fetch_active_threads()
    if not self.http then
        error("Guild has no http client attached, cannot fetch active threads", 0)
    end
    local Route = require("../http/route")
    local Thread = require("./thread")
    local data = Route.new(self.http):get_active_threads(self.id)
    local threads = {}
    for index, thread_data in ipairs(data.threads or {}) do
        threads[index] = Thread.new(thread_data, self, self.http)
    end
    data.threads = threads
    return data
end

function Guild:onboarding()
    if not self.http then error("Guild has no http client attached, cannot fetch onboarding", 0) end
    local Route = require("../http/route")
    local Onboarding = require("./onboarding").Onboarding
    return Onboarding.new(Route.new(self.http):get_onboarding(self.id), self, self.http)
end

function Guild:edit_onboarding(opts)
    if not self.http then error("Guild has no http client attached, cannot edit onboarding", 0) end
    opts = opts or {}
    local payload = {}
    if opts.prompts ~= nil then
        payload.prompts = {}
        for index, prompt in ipairs(opts.prompts) do
            payload.prompts[index] = type(prompt.to_dict) == "function" and prompt:to_dict() or prompt
        end
    end
    if opts.default_channel_ids ~= nil then payload.default_channel_ids = opts.default_channel_ids end
    if opts.default_channels ~= nil then
        payload.default_channel_ids = {}
        for index, channel in ipairs(opts.default_channels) do
            payload.default_channel_ids[index] = type(channel) == "table" and channel.id or channel
        end
    end
    if opts.enabled ~= nil then payload.enabled = opts.enabled end
    if opts.mode ~= nil then payload.mode = opts.mode end
    local Route = require("../http/route")
    local Onboarding = require("./onboarding").Onboarding
    return Onboarding.new(Route.new(self.http):edit_onboarding(self.id, payload, opts.reason), self, self.http)
end

function Guild:modify_incident_actions(opts)
    if not self.http then error("Guild has no http client attached, cannot modify incident actions", 0) end
    opts = opts or {}
    local payload = {}
    if opts.invites_disabled_until ~= nil then payload.invites_disabled_until = opts.invites_disabled_until end
    if opts.dms_disabled_until ~= nil then payload.dms_disabled_until = opts.dms_disabled_until end
    local Route = require("../http/route")
    local IncidentsData = require("./incidents")
    return IncidentsData.new(Route.new(self.http):modify_guild_incident_actions(self.id, payload, opts.reason))
end

return Guild
