-- lib/models/invite.lua
-- Invite model for Discord API
--
-- Public Contract:
--   Invite.new(data, http) -> Invite
--     Creates a new Invite from API data. http is optional, an http.client
--     instance used by :fetch_target_users_job_status/:edit_target_users.
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
--
--   Invite:target_users -> table or nil
--     If this invite was created with target_users_file, a table with
--     :as_user_ids() -> array of user id strings, mirrors pycord's
--     Invite.target_users.as_user_ids(). nil if the invite has no
--     target users restriction.
--
--   invite:fetch_target_users_job_status() -> table
--     GET /invites/{code}/target-users-job. The target_users_file upload
--     Discord uses is processed asynchronously; this reports that job's
--     current status ({status = "pending"|"completed"|"failed", ...}).
--
--   invite:edit_target_users(opts) -> Invite
--     opts.target_users_file: string - CSV content listing target user ids,
--     one per line (matches pycord's users_to_csv output). Note: this
--     codebase's http client is JSON only, so unlike pycord's multipart
--     file upload, the CSV content is sent as a JSON string field rather
--     than an actual file part.

local class = require("core.class")

-- Invite class
local Invite = class("Invite")

local function parse_user_ids_csv(csv)
    if not csv or csv == "" then
        return {}
    end
    local ids = {}
    for line in csv:gmatch("[^\r\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            table.insert(ids, trimmed)
        end
    end
    return ids
end

local function make_target_users(csv)
    return {
        as_user_ids = function(_self)
            return parse_user_ids_csv(csv)
        end,
    }
end

function Invite.new(data, http)
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
    self.http = http

    -- Additional fields
    self.use_count = data.use_count or 0
    self.uses = data.uses or 0

    if data.target_users_file then
        self.target_users = make_target_users(data.target_users_file)
    else
        self.target_users = nil
    end

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

function Invite:fetch_target_users_job_status()
    if not self.http then
        error("Invite has no http client attached, cannot fetch target users job status", 0)
    end

    local Route = require("http.route")
    local route = Route.new(self.http)
    return route:get_invite_target_users_job_status(self.code)
end

function Invite:edit_target_users(opts)
    opts = opts or {}
    if not self.http then
        error("Invite has no http client attached, cannot edit target users", 0)
    end
    if not opts.target_users_file then
        error("Invite:edit_target_users requires opts.target_users_file", 0)
    end

    local Route = require("http.route")
    local route = Route.new(self.http)
    local updated = route:edit_invite_target_users(self.code, {
        target_users_file = opts.target_users_file,
    })

    return Invite.new(updated, self.http)
end

return Invite
