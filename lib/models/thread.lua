-- lib/models/thread.lua
-- Thread model for Discord API. A thread is a specialized channel
-- (Channel:get_type_name() type 13/14/15: news_thread/public_thread/
-- private_thread), so this mirrors channel.lua's data-holding style
-- rather than subclassing it, plus thread_metadata fields and the
-- thread-only actions (join/leave/add_user/remove_user/archive).
--
-- Public Contract:
--   Thread.new(data, guild, http) -> Thread
--     Creates a new Thread from API data (a raw channel payload with
--     a thread_metadata field). guild is optional (stored on
--     self.guild). http is optional, falls back to guild.http.
--
--   Thread:id / :type / :name / :parent_id -> as on Channel
--
--   Thread:owner_id -> string or nil
--     User ID of the thread creator.
--
--   Thread:last_message_id -> string or nil
--
--   Thread:slowmode_delay -> number
--     Renamed from the raw rate_limit_per_user field, mirrors pycord.
--
--   Thread:message_count -> number or nil
--   Thread:member_count -> number or nil
--
--   Thread:archived -> boolean
--   Thread:auto_archive_duration -> number or nil
--   Thread:archive_timestamp -> string or nil
--   Thread:create_timestamp -> string or nil
--   Thread:locked -> boolean
--   Thread:invitable -> boolean
--     From thread_metadata, only meaningful for private threads.
--
--   Thread:is_thread() -> boolean
--
--   Thread:edit(opts) -> Thread (self)
--     PATCH /channels/{id}. opts: name / archived / locked / invitable /
--     slowmode_delay / auto_archive_duration. Mirrors pycord's
--     Thread.edit(). Updates self in place from the response.
--
--   Thread:archive(locked?) -> Thread (self)
--     Shorthand for Thread:edit({ archived = true, locked = locked }).
--
--   Thread:unarchive() -> Thread (self)
--     Shorthand for Thread:edit({ archived = false }).
--
--   Thread:join() -> nil
--     PUT /channels/{id}/thread-members/@me.
--
--   Thread:leave() -> nil
--     DELETE /channels/{id}/thread-members/@me.
--
--   Thread:add_user(user_id) -> nil
--     PUT /channels/{id}/thread-members/{user_id}.
--
--   Thread:remove_user(user_id) -> nil
--     DELETE /channels/{id}/thread-members/{user_id}.
--
--   Thread:fetch_members() -> table
--     GET /channels/{id}/thread-members.
--
--   Thread:delete() -> nil
--     DELETE /channels/{id}.

local class = require("../core/class")

local Thread = class("Thread")

local function apply(self, data)
    self.id = data.id
    self.type = data.type
    self.name = data.name
    self.parent_id = data.parent_id
    self.guild_id = data.guild_id
    self.owner_id = data.owner_id
    self.last_message_id = data.last_message_id
    self.slowmode_delay = data.rate_limit_per_user or 0
    self.message_count = data.message_count
    self.member_count = data.member_count

    local metadata = data.thread_metadata or {}
    self.archived = metadata.archived or false
    self.auto_archive_duration = metadata.auto_archive_duration
    self.archive_timestamp = metadata.archive_timestamp
    self.create_timestamp = metadata.create_timestamp
    self.locked = metadata.locked or false
    if metadata.invitable == nil then
        self.invitable = true
    else
        self.invitable = metadata.invitable
    end
end

function Thread.new(data, guild, http)
    local self = {}
    setmetatable(self, {
        __index = Thread
    })

    apply(self, data)
    self.guild = guild
    self.http = http or (guild and guild.http)

    return self
end

function Thread:is_thread()
    return self.type == 13 or self.type == 14 or self.type == 15
end

function Thread:edit(opts)
    opts = opts or {}
    if not self.http then
        error("Thread has no http client attached, cannot edit", 0)
    end

    local payload = {}
    if opts.name ~= nil then
        payload.name = opts.name
    end
    if opts.archived ~= nil then
        payload.archived = opts.archived
    end
    if opts.locked ~= nil then
        payload.locked = opts.locked
    end
    if opts.invitable ~= nil then
        payload.invitable = opts.invitable
    end
    if opts.slowmode_delay ~= nil then
        payload.rate_limit_per_user = opts.slowmode_delay
    end
    if opts.auto_archive_duration ~= nil then
        payload.auto_archive_duration = opts.auto_archive_duration
    end

    local updated = self.http:patch("/channels/" .. self.id, payload)
    if type(updated) == "table" then
        apply(self, updated)
    end
    return self
end

function Thread:archive(locked)
    return self:edit({ archived = true, locked = locked or false })
end

function Thread:unarchive()
    return self:edit({ archived = false })
end

function Thread:join()
    if not self.http then
        error("Thread has no http client attached, cannot join", 0)
    end
    return self.http:put("/channels/" .. self.id .. "/thread-members/@me")
end

function Thread:leave()
    if not self.http then
        error("Thread has no http client attached, cannot leave", 0)
    end
    return self.http:delete("/channels/" .. self.id .. "/thread-members/@me")
end

function Thread:add_user(user_id)
    if not self.http then
        error("Thread has no http client attached, cannot add_user", 0)
    end
    return self.http:put("/channels/" .. self.id .. "/thread-members/" .. user_id)
end

function Thread:remove_user(user_id)
    if not self.http then
        error("Thread has no http client attached, cannot remove_user", 0)
    end
    return self.http:delete("/channels/" .. self.id .. "/thread-members/" .. user_id)
end

function Thread:fetch_members()
    if not self.http then
        error("Thread has no http client attached, cannot fetch_members", 0)
    end
    return self.http:get("/channels/" .. self.id .. "/thread-members")
end

function Thread:delete()
    if not self.http then
        error("Thread has no http client attached, cannot delete", 0)
    end
    return self.http:delete("/channels/" .. self.id)
end

return Thread
