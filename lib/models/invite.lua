-- lib/models/invite.lua
-- Invite model for Discord API
--
-- Public Contract:
--   Invite.new(data) -> Invite
--     Creates a new Invite from API data.
--
--   Invite:code -> string
--     Invite code.
--
--   Invite:guild -> Guild or nil
--     Guild object.
--
--   Invite:channel -> Channel or nil
--     Channel object.
--
--   Invite:inviter -> User or nil
--     User who created the invite.
--
--   Invite:max_age -> number or nil
--     Maximum age of invite in seconds.
--
--   Invite:max_uses -> number or nil
--     Maximum uses of invite.
--
--   Invite:temporary -> boolean
--     True if invite is temporary.
--
--   Invite:created_at -> string or nil
--     Creation timestamp.

local class = require("core.class")

-- Invite class
local Invite = class("Invite")

function Invite.new(data)
    local self = {}
    setmetatable(self, {
        __index = Invite
    })

    self.code = data.code
    self.guild = data.guild or nil
    self.channel = data.channel or nil
    self.inviter = data.inviter or nil
    self.max_age = data.max_age or nil
    self.max_uses = data.max_uses or nil
    self.temporary = data.temporary or false
    self.created_at = data.created_at or nil

    -- Additional fields
    self.use_count = data.use_count or 0
    self.uses = data.uses or 0

    return self
end

-- Parse ISO 8601 timestamp to Unix timestamp
local function parse_timestamp(ts)
    if not ts then return 0 end
    local unix = tonumber(ts)
    if unix then return unix end

    local year, month, day, hour, min, sec = string.match(ts, "(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)")
    if year then
        return os.time {
            year = tonumber(year),
            month = tonumber(month),
            day = tonumber(day),
            hour = tonumber(hour),
            min = tonumber(min),
            sec = tonumber(sec)
        }
    end
    return 0
end

-- Check if invite is expired
function Invite:is_expired()
    if not self.max_age then
        return false
    end

    local now = os.time()
    local created = parse_timestamp(self.created_at)
    if created == 0 then
        created = now
    end

    return now - created >= self.max_age
end

-- Check if invite is full
function Invite:is_full()
    if not self.max_uses then
        return false
    end

    return self.uses >= self.max_uses
end

return Invite
