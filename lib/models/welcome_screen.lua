-- lib/models/welcome_screen.lua
-- WelcomeScreen model for Discord API
--
-- Public Contract:
--   WelcomeScreen.new(data, guild, http?) -> WelcomeScreen
--     Creates a new WelcomeScreen from a raw API payload. guild is
--     required (stored on self.guild, backs self.enabled via
--     guild.features and self.guild_id for the edit endpoint). http is
--     optional, falls back to guild.http.
--
--   WelcomeScreen:description -> string or nil
--   WelcomeScreen:welcome_channels -> table of WelcomeScreenChannel
--
--   WelcomeScreen:enabled() -> boolean
--     Mirrors pycord's WelcomeScreen.enabled property: true when
--     "WELCOME_SCREEN_ENABLED" is present in guild.features. A method
--     call, not a property (Lua here always uses explicit calls, same
--     as Template:url()). Computed on access rather than cached, since
--     features can change on the attached guild after construction.
--
--   WelcomeScreen:edit(opts) -> WelcomeScreen (self)
--     PATCH /guilds/{guild_id}/welcome-screen. opts.description /
--     opts.welcome_channels (table of WelcomeScreenChannel or plain
--     {channel_id, description, emoji_id?, emoji_name?} tables, both
--     accepted -- see WelcomeScreenChannel:to_dict) / opts.enabled /
--     opts.reason, all optional. Updates self in place from the
--     response.
--
-- WelcomeScreenChannel model, same file (mirrors pycord's
-- discord/welcome_screen.py pairing the two classes together):
--
--   WelcomeScreenChannel.new(channel_id, description, emoji_id?, emoji_name?) -> WelcomeScreenChannel
--     Raw ids only, NOT resolved into a Channel/Emoji instance --
--     Guild here holds no channel cache and guild.emojis is a list of
--     raw payload tables (see NOT_MADE.md pt.1/pt.10 for the same
--     no-cache stance elsewhere), so channel_id/emoji_id/emoji_name
--     stay as plain fields, same as WelcomeScreen.channel/emoji in
--     pycord staying unresolved wherever no cache backs them.
--
--   WelcomeScreenChannel.from_dict(data) -> WelcomeScreenChannel
--     Builds from a raw API welcome_channels[] entry
--     (channel_id/description/emoji_id/emoji_name).
--
--   WelcomeScreenChannel:to_dict() -> table
--     {channel_id, description, emoji_id, emoji_name}, mirrors
--     pycord's WelcomeScreenChannel.to_dict().
--
--   guild:welcome_screen() -> WelcomeScreen
--     GET /guilds/{guild_id}/welcome-screen, mirrors pycord's
--     Guild.welcome_screen().
--
--   guild:edit_welcome_screen(opts) -> WelcomeScreen
--     Shorthand for WelcomeScreen:edit without fetching first, mirrors
--     pycord's Guild.edit_welcome_screen(). Same opts as
--     WelcomeScreen:edit.

local class = require("../core/class")

local WelcomeScreenChannel = class("WelcomeScreenChannel")

function WelcomeScreenChannel.new(channel_id, description, emoji_id, emoji_name)
    local self = {}
    setmetatable(self, { __index = WelcomeScreenChannel })

    self.channel_id = channel_id
    self.description = description
    self.emoji_id = emoji_id
    self.emoji_name = emoji_name

    return self
end

function WelcomeScreenChannel.from_dict(data)
    data = data or {}
    return WelcomeScreenChannel.new(data.channel_id, data.description, data.emoji_id, data.emoji_name)
end

function WelcomeScreenChannel:to_dict()
    return {
        channel_id = self.channel_id,
        description = self.description,
        emoji_id = self.emoji_id,
        emoji_name = self.emoji_name,
    }
end

local WelcomeScreen = class("WelcomeScreen")

local function apply(self, data)
    data = data or {}
    self.description = data.description

    local channels = {}
    for i, channel_data in ipairs(data.welcome_channels or {}) do
        channels[i] = WelcomeScreenChannel.from_dict(channel_data)
    end
    self.welcome_channels = channels
end

function WelcomeScreen.new(data, guild, http)
    local self = {}
    setmetatable(self, { __index = WelcomeScreen })

    apply(self, data)
    self.guild = guild
    self.guild_id = guild and guild.id
    self.http = http or (guild and guild.http)

    return self
end

function WelcomeScreen:enabled()
    if not self.guild or not self.guild.features then
        return false
    end
    for _, feature in ipairs(self.guild.features) do
        if feature == "WELCOME_SCREEN_ENABLED" then
            return true
        end
    end
    return false
end

local function welcome_channels_payload(welcome_channels)
    local payload = {}
    for i, channel in ipairs(welcome_channels or {}) do
        if type(channel.to_dict) == "function" then
            payload[i] = channel:to_dict()
        else
            payload[i] = channel
        end
    end
    return payload
end

function WelcomeScreen:edit(opts)
    opts = opts or {}
    if not self.http then
        error("WelcomeScreen has no http client attached, cannot edit", 0)
    end
    if not self.guild_id then
        error("WelcomeScreen has no guild_id, cannot edit", 0)
    end

    local Route = require("../http/route")
    local route = Route.new(self.http)

    local payload = {}
    if opts.description ~= nil then
        payload.description = opts.description
    end
    if opts.welcome_channels ~= nil then
        payload.welcome_channels = welcome_channels_payload(opts.welcome_channels)
    end
    if opts.enabled ~= nil then
        payload.enabled = opts.enabled
    end

    local updated = route:edit_welcome_screen(self.guild_id, payload, opts.reason)
    if type(updated) == "table" then
        apply(self, updated)
    end

    return self
end

return {
    WelcomeScreen = WelcomeScreen,
    WelcomeScreenChannel = WelcomeScreenChannel,
}
