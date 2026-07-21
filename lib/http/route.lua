-- lib/http/route.lua
-- Centralized REST routes for the core Discord API surface. Wraps an
-- http.client instance so callers do not have to hand build endpoint
-- strings inline, matching pycord's discord/http.py one to one where it
-- fits.
--
-- Public Contract:
--   Route.new(http) -> Route
--     http: an http.client instance.
--
--   Every method below takes the http client's ids as plain arguments and
--   returns whatever http.client:request(...) returns (a decoded table, or
--   throws a typed error from core.errors on failure).

local class = require("core.class")

local Route = class("Route")

function Route.new(http)
    local self = { http = http }
    setmetatable(self, { __index = Route })
    return self
end

local function opts_with_reason(reason)
    if reason then
        return { reason = reason }
    end
    return nil
end

-- Users

function Route:get_user(user_id)
    return self.http:get("/users/" .. user_id)
end

function Route:get_current_user()
    return self.http:get("/users/@me")
end

function Route:edit_current_user(payload)
    return self.http:patch("/users/@me", payload)
end

-- Channels

function Route:get_channel(channel_id)
    return self.http:get("/channels/" .. channel_id)
end

function Route:edit_channel(channel_id, payload, reason)
    return self.http:patch("/channels/" .. channel_id, payload, opts_with_reason(reason))
end

function Route:delete_channel(channel_id, reason)
    return self.http:delete("/channels/" .. channel_id, opts_with_reason(reason))
end

function Route:get_channel_messages(channel_id, params)
    local query = ""
    if params then
        local parts = {}
        for key, value in pairs(params) do
            table.insert(parts, key .. "=" .. tostring(value))
        end
        if #parts > 0 then
            query = "?" .. table.concat(parts, "&")
        end
    end
    return self.http:get("/channels/" .. channel_id .. "/messages" .. query)
end

function Route:edit_channel_permissions(channel_id, target_id, payload, reason)
    return self.http:put(
        "/channels/" .. channel_id .. "/permissions/" .. target_id,
        payload,
        opts_with_reason(reason)
    )
end

function Route:delete_channel_permission(channel_id, target_id, reason)
    return self.http:delete(
        "/channels/" .. channel_id .. "/permissions/" .. target_id,
        opts_with_reason(reason)
    )
end

-- Messages

function Route:send_message(channel_id, payload)
    return self.http:post("/channels/" .. channel_id .. "/messages", payload)
end

function Route:get_message(channel_id, message_id)
    return self.http:get("/channels/" .. channel_id .. "/messages/" .. message_id)
end

function Route:edit_message(channel_id, message_id, payload)
    return self.http:patch("/channels/" .. channel_id .. "/messages/" .. message_id, payload)
end

function Route:delete_message(channel_id, message_id, reason)
    return self.http:delete(
        "/channels/" .. channel_id .. "/messages/" .. message_id,
        opts_with_reason(reason)
    )
end

function Route:bulk_delete_messages(channel_id, message_ids, reason)
    return self.http:post(
        "/channels/" .. channel_id .. "/messages/bulk-delete",
        { messages = message_ids },
        opts_with_reason(reason)
    )
end

-- Guilds

function Route:get_guild(guild_id)
    return self.http:get("/guilds/" .. guild_id)
end

function Route:edit_guild(guild_id, payload, reason)
    return self.http:patch("/guilds/" .. guild_id, payload, opts_with_reason(reason))
end

function Route:get_guild_channels(guild_id)
    return self.http:get("/guilds/" .. guild_id .. "/channels")
end

function Route:create_guild_channel(guild_id, payload, reason)
    return self.http:post("/guilds/" .. guild_id .. "/channels", payload, opts_with_reason(reason))
end

-- Members

function Route:get_member(guild_id, user_id)
    return self.http:get("/guilds/" .. guild_id .. "/members/" .. user_id)
end

function Route:get_members(guild_id, limit, after)
    local query = "?limit=" .. tostring(limit or 1)
    if after then
        query = query .. "&after=" .. tostring(after)
    end
    return self.http:get("/guilds/" .. guild_id .. "/members" .. query)
end

function Route:edit_member(guild_id, user_id, payload, reason)
    return self.http:patch(
        "/guilds/" .. guild_id .. "/members/" .. user_id,
        payload,
        opts_with_reason(reason)
    )
end

function Route:kick(guild_id, user_id, reason)
    return self.http:delete(
        "/guilds/" .. guild_id .. "/members/" .. user_id,
        opts_with_reason(reason)
    )
end

-- Bans

function Route:get_bans(guild_id)
    return self.http:get("/guilds/" .. guild_id .. "/bans")
end

function Route:get_ban(guild_id, user_id)
    return self.http:get("/guilds/" .. guild_id .. "/bans/" .. user_id)
end

function Route:ban(guild_id, user_id, delete_message_seconds, reason)
    local payload = {}
    if delete_message_seconds then
        payload.delete_message_seconds = delete_message_seconds
    end
    return self.http:put(
        "/guilds/" .. guild_id .. "/bans/" .. user_id,
        payload,
        opts_with_reason(reason)
    )
end

function Route:unban(guild_id, user_id, reason)
    return self.http:delete(
        "/guilds/" .. guild_id .. "/bans/" .. user_id,
        opts_with_reason(reason)
    )
end

-- Roles

function Route:get_roles(guild_id)
    return self.http:get("/guilds/" .. guild_id .. "/roles")
end

function Route:create_role(guild_id, payload, reason)
    return self.http:post("/guilds/" .. guild_id .. "/roles", payload, opts_with_reason(reason))
end

function Route:edit_role(guild_id, role_id, payload, reason)
    return self.http:patch(
        "/guilds/" .. guild_id .. "/roles/" .. role_id,
        payload,
        opts_with_reason(reason)
    )
end

function Route:delete_role(guild_id, role_id, reason)
    return self.http:delete(
        "/guilds/" .. guild_id .. "/roles/" .. role_id,
        opts_with_reason(reason)
    )
end

function Route:add_role(guild_id, user_id, role_id, reason)
    return self.http:put(
        "/guilds/" .. guild_id .. "/members/" .. user_id .. "/roles/" .. role_id,
        nil,
        opts_with_reason(reason)
    )
end

function Route:remove_role(guild_id, user_id, role_id, reason)
    return self.http:delete(
        "/guilds/" .. guild_id .. "/members/" .. user_id .. "/roles/" .. role_id,
        opts_with_reason(reason)
    )
end

-- Interaction responses

function Route:create_interaction_response(interaction_id, interaction_token, payload)
    return self.http:post(
        "/interactions/" .. interaction_id .. "/" .. interaction_token .. "/callback",
        payload
    )
end

function Route:edit_interaction_response(application_id, interaction_token, payload)
    return self.http:patch(
        "/webhooks/" .. application_id .. "/" .. interaction_token .. "/messages/@original",
        payload
    )
end

-- Soundboard

function Route:get_default_sounds()
    return self.http:get("/soundboard-default-sounds")
end

function Route:get_guild_sounds(guild_id)
    return self.http:get("/guilds/" .. guild_id .. "/soundboard-sounds")
end

function Route:get_guild_sound(guild_id, sound_id)
    return self.http:get("/guilds/" .. guild_id .. "/soundboard-sounds/" .. sound_id)
end

function Route:create_guild_sound(guild_id, payload, reason)
    return self.http:post("/guilds/" .. guild_id .. "/soundboard-sounds", payload, opts_with_reason(reason))
end

function Route:edit_guild_sound(guild_id, sound_id, payload, reason)
    return self.http:patch(
        "/guilds/" .. guild_id .. "/soundboard-sounds/" .. sound_id,
        payload,
        opts_with_reason(reason)
    )
end

function Route:delete_guild_sound(guild_id, sound_id, reason)
    return self.http:delete(
        "/guilds/" .. guild_id .. "/soundboard-sounds/" .. sound_id,
        opts_with_reason(reason)
    )
end

function Route:send_soundboard_sound(channel_id, payload)
    return self.http:post("/channels/" .. channel_id .. "/send-soundboard-sound", payload)
end

-- Invites

function Route:create_channel_invite(channel_id, payload, reason)
    return self.http:post("/channels/" .. channel_id .. "/invites", payload, opts_with_reason(reason))
end

function Route:get_invite(invite_code, params)
    local query = ""
    if params then
        local parts = {}
        for key, value in pairs(params) do
            table.insert(parts, key .. "=" .. tostring(value))
        end
        if #parts > 0 then
            query = "?" .. table.concat(parts, "&")
        end
    end
    return self.http:get("/invites/" .. invite_code .. query)
end

function Route:delete_invite(invite_code, reason)
    return self.http:delete("/invites/" .. invite_code, opts_with_reason(reason))
end

function Route:get_invite_target_users_job_status(invite_code)
    return self.http:get("/invites/" .. invite_code .. "/target-users-job")
end

function Route:edit_invite_target_users(invite_code, payload)
    return self.http:patch("/invites/" .. invite_code .. "/target-users", payload)
end

return Route
