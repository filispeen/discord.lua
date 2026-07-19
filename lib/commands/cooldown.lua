-- lib/commands/cooldown.lua
-- Cooldown support for ext.commands, contract mirrors pycord commands.Cooldown /
-- commands.cooldown / commands.dynamic_cooldown / commands.BucketType.
--
-- Public Contract:
--   BucketType: table of bucket key functions, {default, user, guild, channel, member, category, role}
--     Each entry is a function(ctx) -> key used to bucket cooldown state.
--
--   Cooldown.new(rate, per) -> cooldown
--     rate: number - how many uses are allowed
--     per: number - the time window in seconds
--
--   cooldown:update(current_time) -> retry_after
--     current_time: number or nil, defaults to os.time()
--     Returns 0 if the call is allowed (and records it), otherwise the
--     number of seconds left before the next call is allowed.
--
--   cooldown:reset() -> nil
--     Clears all recorded call timestamps.
--
--   cooldown:copy() -> cooldown
--     Returns a fresh Cooldown with the same rate/per and no history,
--     used per-bucket-key so buckets don't share state.
--
--   M.cooldown(rate, per, bucket_type) -> check_table
--     Returns a check table (matches lib/commands/checks.lua Check shape)
--     whose func(ctx) raises CommandOnCooldown when on cooldown, otherwise
--     returns true. bucket_type defaults to BucketType.user.
--
--   M.dynamic_cooldown(callback, bucket_type) -> check_table
--     callback(ctx) -> Cooldown or nil. nil bypasses the cooldown entirely
--     for that invocation, matching pycord's dynamic_cooldown semantics.
--
--   M.CommandOnCooldown(retry_after) -> exception
--     Raised (via error(...)) when a command is invoked while on cooldown.
--     retry_after: number - seconds remaining before the command becomes usable again.

local class = require("core.class")
local errors = require("core.errors")

local CommandOnCooldown = class("CommandOnCooldown", errors.DiscordException)

function CommandOnCooldown.new(retry_after)
    local self = setmetatable({}, CommandOnCooldown)
    self.message = "Command is on cooldown"
    self.retry_after = retry_after or 0
    return self
end

CommandOnCooldown.create = CommandOnCooldown.new

function CommandOnCooldown:__tostring()
    return "CommandOnCooldown: retry in " .. tostring(self.retry_after) .. "s"
end

local function extract_id_from_author(ctx)
    local author = ctx.author
    if type(author) == "table" then
        if type(author.id) == "table" then
            return author.id.id or author.id.username or author.id.global_name
        end
        return author.id
    end
    return author
end

local function extract_id_from_guild(ctx)
    local guild = ctx.guild
    if type(guild) == "table" then
        if type(guild.id) == "table" then
            return guild.id.id or guild.id.name
        end
        return guild.id
    end
    return guild
end

local function extract_id_from_channel(ctx)
    local channel = ctx.channel
    if type(channel) == "table" then
        if type(channel.id) == "table" then
            return channel.id.id
        end
        return channel.id
    end
    return channel
end

-- BucketType: each function returns a bucketing key for a ctx, or nil
-- (nil keys still work, they just all collapse into a single "global" bucket).
local BucketType = {
    default = function(_ctx)
        return "default"
    end,
    user = function(ctx)
        return "user:" .. tostring(extract_id_from_author(ctx))
    end,
    guild = function(ctx)
        return "guild:" .. tostring(extract_id_from_guild(ctx))
    end,
    channel = function(ctx)
        return "channel:" .. tostring(extract_id_from_channel(ctx))
    end,
    member = function(ctx)
        return "member:" .. tostring(extract_id_from_guild(ctx)) .. ":" .. tostring(extract_id_from_author(ctx))
    end,
}

local Cooldown = class("Cooldown")

function Cooldown.new(rate, per)
    local self = setmetatable({}, Cooldown)
    self.rate = rate
    self.per = per
    self._calls = {}
    return self
end

-- Drops timestamps older than the window, keeping only calls still inside `per`.
function Cooldown:_prune(current_time)
    local window_start = current_time - self.per
    local kept = {}
    for _, timestamp in ipairs(self._calls) do
        if timestamp > window_start then
            table.insert(kept, timestamp)
        end
    end
    self._calls = kept
end

-- Records a call attempt at current_time (defaults to os.time()).
-- Returns 0 if allowed, otherwise seconds remaining before the oldest
-- call in the window expires.
function Cooldown:update(current_time)
    current_time = current_time or os.time()
    self:_prune(current_time)

    if #self._calls < self.rate then
        table.insert(self._calls, current_time)
        return 0
    end

    local oldest = self._calls[1]
    local retry_after = self.per - (current_time - oldest)
    if retry_after < 0 then
        retry_after = 0
    end
    return retry_after
end

function Cooldown:reset()
    self._calls = {}
end

function Cooldown:copy()
    return Cooldown.new(self.rate, self.per)
end

local M = {
    BucketType = BucketType,
    Cooldown = Cooldown,
    CommandOnCooldown = CommandOnCooldown,
}

-- Builds a check table (same shape as lib/commands/checks.lua) that enforces
-- a static rate/per cooldown, bucketed by bucket_type (defaults to per-user).
function M.cooldown(rate, per, bucket_type)
    bucket_type = bucket_type or BucketType.user
    local buckets = {}

    return {
        name = "cooldown",
        func = function(ctx)
            local key = bucket_type(ctx)
            local bucket = buckets[key]
            if not bucket then
                bucket = Cooldown.new(rate, per)
                buckets[key] = bucket
            end

            local retry_after = bucket:update()
            if retry_after > 0 then
                error(CommandOnCooldown.new(retry_after), 0)
            end
            return true
        end,
    }
end

-- Builds a check table whose per-invocation Cooldown is produced by
-- callback(ctx). callback returning nil bypasses the cooldown for that call.
function M.dynamic_cooldown(callback, bucket_type)
    bucket_type = bucket_type or BucketType.user
    local buckets = {}

    return {
        name = "dynamic_cooldown",
        func = function(ctx)
            local template = callback(ctx)
            if template == nil then
                return true
            end

            local key = bucket_type(ctx)
            local bucket = buckets[key]
            if not bucket or bucket.rate ~= template.rate or bucket.per ~= template.per then
                bucket = template:copy()
                buckets[key] = bucket
            end

            local retry_after = bucket:update()
            if retry_after > 0 then
                error(CommandOnCooldown.new(retry_after), 0)
            end
            return true
        end,
    }
end

return M
