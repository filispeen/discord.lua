-- lib/models/widget.lua
-- Widget model for Discord API
--
-- Public Contract:
--   WidgetChannel.new(id, name, position) -> WidgetChannel
--     Raw partial channel as it appears inside a widget payload.
--
--   WidgetChannel:mention() -> string
--     "<#id>", mirrors pycord's WidgetChannel.mention property (a
--     method here, not a property, same explicit-call style as
--     Template:url()/WelcomeScreen:enabled()).
--
--   WidgetMember.new(data, connected_channel?) -> WidgetMember
--     Partial member as it appears inside a widget payload. Not a
--     User subclass (this project's User.new takes only (data), no
--     inheritance hook here) -- instead duplicates the same base
--     fields (id/username/discriminator/avatar/bot) directly on
--     self, same flattening choice as PollAnswer over PollMedia
--     (NOT_MADE.md pt.5). connected_channel is an already-built
--     WidgetChannel or nil, resolved by Widget.new before
--     construction.
--
--   WidgetMember:activity -> table or nil
--     Raw "game" payload field, unwrapped -- pycord's create_activity
--     (NOT_MADE.md pt.14, Presence/Activity) does not exist in this
--     project, so this stays a plain table same as everywhere else in
--     this session no activity-model exists yet.
--
--   Widget.new(data, http?) -> Widget
--     Creates a new Widget from a GET .../widget.json response.
--     http is optional, backs Widget:fetch_invite.
--
--   Widget:id -> string
--   Widget:name -> string
--   Widget:channels -> table of WidgetChannel
--   Widget:members -> table of WidgetMember
--
--   Widget:json_url() -> string
--     "https://discord.com/api/guilds/{id}/widget.json", mirrors
--     pycord's Widget.json_url property (method here, same style).
--
--   Widget:invite_url() -> string or nil
--     The raw instant_invite string from the payload, mirrors
--     pycord's Widget.invite_url property.
--
--   Widget:fetch_invite(with_counts?) -> Invite
--     Resolves the widget's invite_url into a full Invite via
--     GET /invites/{code}, mirrors pycord's Widget.fetch_invite.
--     with_counts defaults to true, same default as pycord.
--
--   client:fetch_widget(guild_id) -> Widget
--     GET /guilds/{guild_id}/widget.json, mirrors pycord's
--     Client.fetch_widget. Same Client-level HTTP-fetch style as
--     Client:fetch_template (NOT_MADE.md pt.11) -- a widget is
--     fetched by guild_id directly, no guild instance required.
--
--   guild:widget() -> Widget
--     GET /guilds/{guild_id}/widget.json, mirrors pycord's
--     Guild.widget().
--
--   guild:edit_widget(opts) -> nil
--     PATCH /guilds/{guild_id}/widget. opts.enabled / opts.channel_id
--     (nil clears the widget channel), both optional, mirrors
--     pycord's Guild.edit_widget(enabled=..., channel=...). The
--     endpoint returns the updated WidgetSettings body but pycord's
--     own edit_widget discards it (returns None) -- same choice here,
--     nothing to build a WidgetSettings class for since nothing in
--     this project reads it back.

local class = require("../core/class")

local WidgetChannel = class("WidgetChannel")

function WidgetChannel.new(id, name, position)
    local self = {}
    setmetatable(self, { __index = WidgetChannel })

    self.id = id
    self.name = name
    self.position = position

    return self
end

function WidgetChannel:mention()
    return "<#" .. self.id .. ">"
end

local WidgetMember = class("WidgetMember")

function WidgetMember.new(data, connected_channel)
    data = data or {}
    local self = {}
    setmetatable(self, { __index = WidgetMember })

    self.id = data.id
    self.username = data.username
    self.discriminator = data.discriminator
    self.avatar = data.avatar
    self.bot = data.bot or false
    self.nick = data.nick
    self.status = data.status
    self.deafened = data.deaf or data.self_deaf or false
    self.muted = data.mute or data.self_mute or false
    self.suppress = data.suppress or false
    self.activity = data.game
    self.connected_channel = connected_channel

    return self
end

function WidgetMember:display_name()
    return self.nick or self.username
end

local Widget = class("Widget")

function Widget.new(data, http)
    data = data or {}
    local self = {}
    setmetatable(self, { __index = Widget })

    self.id = data.id
    self.name = data.name
    self._invite = data.instant_invite
    self.http = http

    local channels = {}
    local channels_by_id = {}
    for i, channel_data in ipairs(data.channels or {}) do
        local channel = WidgetChannel.new(channel_data.id, channel_data.name, channel_data.position)
        channels[i] = channel
        channels_by_id[channel.id] = channel
    end
    self.channels = channels

    local members = {}
    for i, member_data in ipairs(data.members or {}) do
        local connected_channel = nil
        local channel_id = member_data.channel_id
        if channel_id then
            connected_channel = channels_by_id[channel_id] or WidgetChannel.new(channel_id, "", 0)
        end
        members[i] = WidgetMember.new(member_data, connected_channel)
    end
    self.members = members

    return self
end

function Widget:json_url()
    return "https://discord.com/api/guilds/" .. self.id .. "/widget.json"
end

function Widget:invite_url()
    return self._invite
end

function Widget:fetch_invite(with_counts)
    if not self.http then
        error("Widget has no http client attached, cannot fetch invite", 0)
    end
    if not self._invite then
        error("Widget has no invite_url, cannot fetch invite", 0)
    end
    if with_counts == nil then
        with_counts = true
    end

    local resolved = self._invite:match("^https?://discord%.gg/(.+)$")
        or self._invite:match("^discord%.gg/(.+)$")
        or self._invite

    local Route = require("../http/route")
    local Invite = require("./invite")
    local route = Route.new(self.http)

    local data = route:get_invite(resolved, { with_counts = with_counts })
    return Invite.new(data, self.http)
end

return {
    Widget = Widget,
    WidgetChannel = WidgetChannel,
    WidgetMember = WidgetMember,
}
