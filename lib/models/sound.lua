-- lib/models/sound.lua
-- Soundboard Sound model for Discord API, contract mirrors pycord's
-- discord.SoundboardSound.
--
-- Public Contract:
--   Sound.new(data, guild_id, http) -> Sound
--     data: raw soundboard sound payload from the API
--     guild_id: string or nil - nil for a default (non-guild) sound
--     http: an http.client instance, used by :edit/:delete
--
--   Sound:id -> string
--   Sound:name -> string
--   Sound:volume -> number
--   Sound:emoji -> table or nil - {id, name} shaped like a partial emoji
--   Sound:available -> boolean
--   Sound:guild_id -> string or nil
--
--   sound:edit(opts) -> Sound
--     opts.name / opts.volume / opts.emoji_id / opts.emoji_name: any subset,
--     unset fields keep their current value. Only valid for guild sounds.
--
--   sound:delete(reason) -> nil
--     Only valid for guild sounds.

local class = require("core.class")
local Route = require("http.route")

local Sound = class("Sound")

function Sound.new(data, guild_id, http)
    local self = setmetatable({}, Sound)

    self.id = data.sound_id or data.id
    self.name = data.name
    self.volume = data.volume or 1.0
    self.available = data.available
    if self.available == nil then
        self.available = true
    end

    if data.emoji_id or data.emoji_name then
        self.emoji = { id = data.emoji_id, name = data.emoji_name }
    else
        self.emoji = nil
    end

    self.guild_id = guild_id
    self.http = http

    return self
end

function Sound:edit(opts)
    opts = opts or {}
    if not self.guild_id then
        error("cannot edit a default soundboard sound", 0)
    end
    if not self.http then
        error("Sound has no http client attached, cannot edit", 0)
    end

    local payload = {
        name = opts.name or self.name,
        volume = opts.volume or self.volume,
    }
    if opts.emoji_id ~= nil or opts.emoji_name ~= nil then
        payload.emoji_id = opts.emoji_id
        payload.emoji_name = opts.emoji_name
    elseif self.emoji then
        payload.emoji_id = self.emoji.id
        payload.emoji_name = self.emoji.name
    end

    local route = Route.new(self.http)
    local updated = route:edit_guild_sound(self.guild_id, self.id, payload, opts.reason)
    return Sound.new(updated, self.guild_id, self.http)
end

function Sound:delete(reason)
    if not self.guild_id then
        error("cannot delete a default soundboard sound", 0)
    end
    if not self.http then
        error("Sound has no http client attached, cannot delete", 0)
    end

    local route = Route.new(self.http)
    return route:delete_guild_sound(self.guild_id, self.id, reason)
end

return Sound
