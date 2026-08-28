-- lib/models/activity.lua
-- Activity models for Discord's rich presence, used both to build the
-- activity a bot sends via Client:change_presence and to parse the
-- activities other users' PRESENCE_UPDATE payloads carry.
--
-- Public Contract:
--   Activity.new(data) -> Activity
--     Full-featured activity, covers any activity payload that does not
--     fit the slimmed down Game/Streaming/CustomActivity/Spotify cases
--     below (e.g. a received "playing" activity with application_id/
--     session_id set -- a rich presence game, not a plain Game).
--     Fields: .state / .details / .timestamps / .assets / .party /
--     .flags / .sync_id / .session_id / .buttons / .type (raw
--     ActivityType int, see enums.ACTIVITY_TYPE, no enum wrapper --
--     same no-wrapper convention as e.g. ScheduledEvent.status) /
--     .name / .url / .application_id / .emoji (raw {id?, name,
--     animated?} table or nil, same no-wrap convention as
--     Reaction.emoji) / .created_at (raw ms unix timestamp or nil, not
--     parsed into any date/time value -- this project has no
--     datetime utility, same stance as Message.timestamp staying a
--     raw ISO 8601 string).
--   Activity:to_dict() -> table
--     Payload form for sending via Client:change_presence, omits any
--     field left nil/empty (mirrors pycord's Activity.to_dict).
--   Activity:large_image_url() / :small_image_url() -> string or nil
--   Activity:large_image_text() / :small_image_text() -> string or nil
--
--   Game.new(name, opts?) -> Game
--     Slimmed down "Playing X" activity. opts.timestamps = {start?,
--     finish?} (named .finish, not .end -- end is a reserved word in
--     Lua and cannot be used as a table field after a dot; this is the
--     one deliberate field rename against pycord's ActivityTimestamps
--     "end" key, the wire payload built by :to_dict() below still uses
--     the real "end" key since that is written with bracket syntax,
--     not dot syntax). opts.created_at optional.
--   Game:to_dict() -> table
--
--   Streaming.new(opts) -> Streaming
--     opts.name (platform, e.g. "Twitch"), opts.url (required by
--     Discord), opts.details/opts.state (mirrors pycord's odd
--     name/details aliasing), opts.assets.
--   Streaming:twitch_name() -> string or nil
--     assets.large_image with the "twitch:" prefix stripped, nil if
--     absent or a different prefix.
--   Streaming:to_dict() -> table
--
--   CustomActivity.new(name, opts?) -> CustomActivity
--     opts.state (defaults to name), opts.emoji (nil, a plain unicode
--     string treated as the emoji name, or a raw {id?, name, animated?}
--     table -- same no-PartialEmoji-class convention as
--     Reaction.emoji/PollMedia.emoji elsewhere in this project).
--   CustomActivity:to_dict() -> table
--
--   Spotify.new(data) -> Spotify
--     Read-only wrapper around a received Spotify listening activity
--     (type=listening with sync_id/session_id set). Never meant to be
--     sent via change_presence -- Discord does not treat bot-sent
--     Spotify activities as real listening sessions, this class exists
--     purely to make sense of PRESENCE_UPDATE payloads, same as pycord.
--   Spotify:title() / :artist() / :artists() (array, split on "; ") /
--   Spotify:album() / :album_cover_url() / :track_id() / :track_url() /
--   Spotify:start_time() / :end_time() / :duration_ms() / :party_id() /
--   Spotify:colour() (0x1DB954, Spotify's brand colour, as a plain int)
--     -> as pycord's equivalent properties, all methods here since Lua
--     always makes explicit calls (no @property machinery).
--   Spotify:to_dict() -> table
--
--   create_activity(data) -> Activity/Game/Streaming/CustomActivity/Spotify/nil
--     Picks the concrete wrapper class from a raw activity payload's
--     .type, mirrors pycord's activity.py create_activity: playing
--     with application_id/session_id -> Activity, playing otherwise ->
--     Game, custom with a name -> CustomActivity, streaming with a url
--     -> Streaming, listening with sync_id+session_id -> Spotify,
--     anything else -> Activity. nil in, nil out. Not wired into
--     PRESENCE_UPDATE dispatch automatically (lib/models/client.lua
--     keeps that raw, same no-cache-model stance as the rest of this
--     session) -- callers who want parsed activities call this
--     themselves against the raw payload.

local class = require("../core/class")
local enums = require("../core/enums")

local BaseActivity = class("BaseActivity")
local Activity = class("Activity", BaseActivity)
local Game = class("Game", BaseActivity)
local Streaming = class("Streaming", BaseActivity)
local CustomActivity = class("CustomActivity", BaseActivity)
local Spotify = class("Spotify")

local ASSET_BASE = "https://cdn.discordapp.com"

-- Activity

function Activity.new(data)
    data = data or {}
    local self = {}
    setmetatable(self, { __index = Activity })

    self.state = data.state
    self.details = data.details
    self.timestamps = data.timestamps or {}
    self.assets = data.assets or {}
    self.party = data.party or {}
    self.application_id = data.application_id
    self.url = data.url
    self.flags = data.flags or 0
    self.sync_id = data.sync_id
    self.session_id = data.session_id
    self.buttons = data.buttons or {}
    self.type = data.type
    if self.type == nil then
        self.type = -1
    end
    self.name = data.name
    if self.name == nil and self.type == enums.ACTIVITY_TYPE.CUSTOM then
        self.name = "Custom Status"
    end
    self.emoji = data.emoji
    self.created_at = data.created_at

    return self
end

function Activity:to_dict()
    local ret = {}
    if self.state ~= nil then ret.state = self.state end
    if self.details ~= nil then ret.details = self.details end
    if self.timestamps and next(self.timestamps) ~= nil then ret.timestamps = self.timestamps end
    if self.assets and next(self.assets) ~= nil then ret.assets = self.assets end
    if self.party and next(self.party) ~= nil then ret.party = self.party end
    if self.flags and self.flags ~= 0 then ret.flags = self.flags end
    if self.sync_id ~= nil then ret.sync_id = self.sync_id end
    if self.session_id ~= nil then ret.session_id = self.session_id end
    if self.name ~= nil then ret.name = self.name end
    if self.url ~= nil then ret.url = self.url end
    if self.application_id ~= nil then ret.application_id = self.application_id end
    if self.buttons and #self.buttons > 0 then ret.buttons = self.buttons end
    ret.type = self.type
    if self.emoji ~= nil then ret.emoji = self.emoji end
    return ret
end

function Activity:large_image_url()
    if self.application_id == nil then return nil end
    local large_image = self.assets.large_image
    if not large_image then return nil end
    return ASSET_BASE .. "/app-assets/" .. tostring(self.application_id) .. "/" .. large_image .. ".png"
end

function Activity:small_image_url()
    if self.application_id == nil then return nil end
    local small_image = self.assets.small_image
    if not small_image then return nil end
    return ASSET_BASE .. "/app-assets/" .. tostring(self.application_id) .. "/" .. small_image .. ".png"
end

function Activity:large_image_text()
    return self.assets.large_text
end

function Activity:small_image_text()
    return self.assets.small_text
end

-- Game

function Game.new(name, opts)
    opts = opts or {}
    local self = {}
    setmetatable(self, { __index = Game })

    self.name = name
    self.type = enums.ACTIVITY_TYPE.PLAYING

    local timestamps = opts.timestamps or {}
    self.start = timestamps.start or 0
    self.finish = timestamps["end"] or 0
    self.created_at = opts.created_at

    return self
end

function Game:to_dict()
    local timestamps = {}
    if self.start and self.start ~= 0 then timestamps.start = self.start end
    if self.finish and self.finish ~= 0 then timestamps["end"] = self.finish end

    return {
        type = enums.ACTIVITY_TYPE.PLAYING,
        name = tostring(self.name),
        timestamps = timestamps,
    }
end

-- Streaming

function Streaming.new(opts)
    opts = opts or {}
    local self = {}
    setmetatable(self, { __index = Streaming })

    self.platform = opts.name
    self.name = opts.details or opts.name
    self.game = opts.state
    self.url = opts.url
    self.details = opts.details or self.name
    self.assets = opts.assets or {}
    self.type = enums.ACTIVITY_TYPE.STREAMING
    self.created_at = opts.created_at

    return self
end

function Streaming:twitch_name()
    local large_image = self.assets.large_image
    if not large_image then return nil end
    if large_image:sub(1, 7) == "twitch:" then
        return large_image:sub(8)
    end
    return nil
end

function Streaming:to_dict()
    local ret = {
        type = enums.ACTIVITY_TYPE.STREAMING,
        name = tostring(self.name),
        url = tostring(self.url),
        assets = self.assets,
    }
    if self.details then ret.details = self.details end
    return ret
end

-- CustomActivity

function CustomActivity.new(name, opts)
    opts = opts or {}
    local self = {}
    setmetatable(self, { __index = CustomActivity })

    self.state = opts.state or name
    self.name = name
    if self.name == "Custom Status" then
        self.name = self.state
    end

    local emoji = opts.emoji
    if emoji == nil then
        self.emoji = nil
    elseif type(emoji) == "string" then
        self.emoji = { name = emoji }
    elseif type(emoji) == "table" then
        self.emoji = emoji
    else
        error("CustomActivity emoji must be a string, a raw emoji table, or nil", 0)
    end

    self.type = enums.ACTIVITY_TYPE.CUSTOM
    self.created_at = opts.created_at

    return self
end

function CustomActivity:to_dict()
    local o
    if self.name == self.state then
        o = { type = enums.ACTIVITY_TYPE.CUSTOM, state = self.name, name = "Custom Status" }
    else
        o = { type = enums.ACTIVITY_TYPE.CUSTOM, name = self.name }
    end
    if self.emoji then o.emoji = self.emoji end
    return o
end

-- Spotify

local function split_artists(state)
    local out = {}
    for part in string.gmatch(state or "", "([^;]+)") do
        table.insert(out, (part:gsub("^%s+", "")))
    end
    return out
end

function Spotify.new(data)
    data = data or {}
    local self = {}
    setmetatable(self, { __index = Spotify })

    self._state = data.state or ""
    self._details = data.details or ""
    self._timestamps = data.timestamps or {}
    self._assets = data.assets or {}
    self._party = data.party or {}
    self._sync_id = data.sync_id
    self._session_id = data.session_id
    self.created_at = data.created_at
    self.type = enums.ACTIVITY_TYPE.LISTENING
    self.name = "Spotify"

    return self
end

function Spotify:title()
    return self._details
end

function Spotify:artist()
    return self._state
end

function Spotify:artists()
    return split_artists(self._state)
end

function Spotify:album()
    return self._assets.large_text or ""
end

function Spotify:album_cover_url()
    local large_image = self._assets.large_image or ""
    if large_image:sub(1, 8) ~= "spotify:" then return "" end
    return "https://i.scdn.co/image/" .. large_image:sub(9)
end

function Spotify:track_id()
    return self._sync_id
end

function Spotify:track_url()
    return "https://open.spotify.com/track/" .. tostring(self._sync_id)
end

function Spotify:start_time()
    return self._timestamps.start
end

function Spotify:end_time()
    return self._timestamps["end"]
end

function Spotify:duration_ms()
    local start_ms, end_ms = self._timestamps.start, self._timestamps["end"]
    if not start_ms or not end_ms then return nil end
    return end_ms - start_ms
end

function Spotify:party_id()
    return self._party.id or ""
end

function Spotify:colour()
    return 0x1DB954
end
Spotify.color = Spotify.colour

function Spotify:to_dict()
    return {
        flags = 48,
        name = "Spotify",
        assets = self._assets,
        party = self._party,
        sync_id = self._sync_id,
        session_id = self._session_id,
        timestamps = self._timestamps,
        details = self._details,
        state = self._state,
    }
end

-- Factory

local function create_activity(data)
    if not data then return nil end

    local game_type = data.type
    if game_type == nil then game_type = -1 end

    if game_type == enums.ACTIVITY_TYPE.PLAYING then
        if data.application_id ~= nil or data.session_id ~= nil then
            return Activity.new(data)
        end
        return Game.new(data.name, data)
    elseif game_type == enums.ACTIVITY_TYPE.CUSTOM then
        if data.name == nil then
            return Activity.new(data)
        end
        local without_name = {}
        for k, v in pairs(data) do
            if k ~= "name" then without_name[k] = v end
        end
        return CustomActivity.new(data.name, without_name)
    elseif game_type == enums.ACTIVITY_TYPE.STREAMING then
        if data.url ~= nil then
            return Streaming.new(data)
        end
        return Activity.new(data)
    elseif game_type == enums.ACTIVITY_TYPE.LISTENING and data.sync_id ~= nil and data.session_id ~= nil then
        return Spotify.new(data)
    end

    return Activity.new(data)
end

return {
    BaseActivity = BaseActivity,
    Activity = Activity,
    Game = Game,
    Streaming = Streaming,
    CustomActivity = CustomActivity,
    Spotify = Spotify,
    create_activity = create_activity,
}
