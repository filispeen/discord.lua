-- lib/models/member.lua
-- Guild member model and moderation helpers.

local class = require("../core/class")

local Member = class("Member")

local function apply(self, data)
    self.user = data.user or self.user
    self.id = (self.user and self.user.id) or data.user_id or self.id
    self.roles = data.roles or {}
    self.joined_at = data.joined_at
    self.deaf = data.deaf or false
    self.mute = data.mute or false
    self.pending = data.pending or false
    self.nick = data.nick
    self.communication_disabled_until = data.communication_disabled_until
    self.joined_at_epoch = self.joined_at
end

function Member.new(data, guild)
    local self = setmetatable({ guild = guild }, { __index = Member })
    apply(self, data)
    return self
end

function Member:get_role_id(role)
    for _, r in ipairs(self.roles) do
        if r.id == role.id or r.name == role.name then return r.id end
    end
end

function Member:has_role(role)
    for _, r in ipairs(self.roles) do
        if r.id == role.id or r.name == role.name then return true end
    end
    return false
end

-- Sets or clears (with nil) Discord's communication timeout. until accepts
-- an ISO8601 timestamp or Unix timestamp; Discord enforces its 28-day limit.
function Member:timeout(timestamp, reason)
    if not self.guild or not self.guild.id or not self.id then
        error("Member:timeout() requires a member with guild and user ids", 0)
    end
    if timestamp ~= nil and type(timestamp) ~= "string" then
        if type(timestamp) ~= "number" then
            error("Member:timeout() until must be an ISO8601 string, Unix timestamp, or nil", 0)
        end
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ", timestamp)
    end
    local http = self.guild.http
    if not http then error("Member has no http client attached, cannot timeout", 0) end
    local Route = require("../http/route")
    local data = Route.new(http):edit_member(self.guild.id, self.id, {
        communication_disabled_until = timestamp,
    }, reason)
    if type(data) == "table" then apply(self, data) else self.communication_disabled_until = timestamp end
    return self
end

function Member:remove_timeout(reason)
    return self:timeout(nil, reason)
end

return Member
