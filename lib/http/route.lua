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

local class = require("../core/class")

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

function Route:send_message(channel_id, payload, files)
    if files and #files > 0 then
        local Multipart = require("./multipart")
        return self.http:post_multipart(
            "/channels/" .. channel_id .. "/messages",
            Multipart.with_attachments(payload, files),
            files
        )
    end
    return self.http:post("/channels/" .. channel_id .. "/messages", payload)
end

function Route:get_message(channel_id, message_id)
    return self.http:get("/channels/" .. channel_id .. "/messages/" .. message_id)
end

function Route:edit_message(channel_id, message_id, payload, files)
    if files and #files > 0 then
        local Multipart = require("./multipart")
        return self.http:patch_multipart(
            "/channels/" .. channel_id .. "/messages/" .. message_id,
            Multipart.with_attachments(payload, files),
            files
        )
    end
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

function Route:pin_message(channel_id, message_id, reason)
    return self.http:put("/channels/" .. channel_id .. "/pins/" .. message_id, nil, opts_with_reason(reason))
end

function Route:unpin_message(channel_id, message_id, reason)
    return self.http:delete("/channels/" .. channel_id .. "/pins/" .. message_id, opts_with_reason(reason))
end

function Route:get_reaction_users(channel_id, message_id, emoji, params)
    local query = ""
    if params then
        local parts = {}
        for key, value in pairs(params) do
            parts[#parts + 1] = key .. "=" .. tostring(value)
        end
        if #parts > 0 then
            query = "?" .. table.concat(parts, "&")
        end
    end
    return self.http:get("/channels/" .. channel_id .. "/messages/" .. message_id .. "/reactions/" .. emoji .. query)
end

function Route:get_active_threads(guild_id)
    return self.http:get("/guilds/" .. guild_id .. "/threads/active")
end

function Route:get_archived_threads(channel_id, kind, params)
    local suffix = kind == "private" and "/private" or "/public"
    if kind == "joined_private" then
        suffix = "/users/@me/threads/archived/private"
        return self.http:get("/channels/" .. channel_id .. suffix)
    end
    local query = ""
    if params then
        local parts = {}
        for key, value in pairs(params) do
            parts[#parts + 1] = key .. "=" .. tostring(value)
        end
        if #parts > 0 then
            query = "?" .. table.concat(parts, "&")
        end
    end
    return self.http:get("/channels/" .. channel_id .. "/threads/archived" .. suffix .. query)
end

function Route:create_webhook(channel_id, payload, reason)
    return self.http:post("/channels/" .. channel_id .. "/webhooks", payload, opts_with_reason(reason))
end

function Route:get_channel_webhooks(channel_id)
    return self.http:get("/channels/" .. channel_id .. "/webhooks")
end

function Route:follow_channel(channel_id, webhook_channel_id, reason)
    return self.http:post(
        "/channels/" .. channel_id .. "/followers",
        { webhook_channel_id = webhook_channel_id },
        opts_with_reason(reason)
    )
end

function Route:get_webhook(webhook_id)
    return self.http:get("/webhooks/" .. webhook_id)
end

function Route:get_webhook_with_token(webhook_id, webhook_token)
    return self.http:get("/webhooks/" .. webhook_id .. "/" .. webhook_token)
end

function Route:edit_webhook(webhook_id, payload, reason)
    return self.http:patch("/webhooks/" .. webhook_id, payload, opts_with_reason(reason))
end

function Route:delete_webhook(webhook_id, reason)
    return self.http:delete("/webhooks/" .. webhook_id, opts_with_reason(reason))
end

function Route:get_guild_emojis(guild_id)
    return self.http:get("/guilds/" .. guild_id .. "/emojis")
end

function Route:create_guild_emoji(guild_id, payload, reason)
    return self.http:post("/guilds/" .. guild_id .. "/emojis", payload, opts_with_reason(reason))
end

function Route:edit_guild_emoji(guild_id, emoji_id, payload, reason)
    return self.http:patch("/guilds/" .. guild_id .. "/emojis/" .. emoji_id, payload, opts_with_reason(reason))
end

function Route:delete_guild_emoji(guild_id, emoji_id, reason)
    return self.http:delete("/guilds/" .. guild_id .. "/emojis/" .. emoji_id, opts_with_reason(reason))
end

function Route:get_application_emojis(application_id)
    return self.http:get("/applications/" .. application_id .. "/emojis")
end

function Route:create_application_emoji(application_id, payload)
    return self.http:post("/applications/" .. application_id .. "/emojis", payload)
end

function Route:edit_application_emoji(application_id, emoji_id, payload)
    return self.http:patch("/applications/" .. application_id .. "/emojis/" .. emoji_id, payload)
end

function Route:delete_application_emoji(application_id, emoji_id)
    return self.http:delete("/applications/" .. application_id .. "/emojis/" .. emoji_id)
end

function Route:get_guild_stickers(guild_id)
    return self.http:get("/guilds/" .. guild_id .. "/stickers")
end

function Route:get_guild_sticker(guild_id, sticker_id)
    return self.http:get("/guilds/" .. guild_id .. "/stickers/" .. sticker_id)
end

function Route:create_guild_sticker(guild_id, payload, files, reason)
    if files and #files > 0 then
        return self.http:post_multipart("/guilds/" .. guild_id .. "/stickers", payload, files, opts_with_reason(reason))
    end
    return self.http:post("/guilds/" .. guild_id .. "/stickers", payload, opts_with_reason(reason))
end

function Route:edit_guild_sticker(guild_id, sticker_id, payload, reason)
    return self.http:patch("/guilds/" .. guild_id .. "/stickers/" .. sticker_id, payload, opts_with_reason(reason))
end

function Route:delete_guild_sticker(guild_id, sticker_id, reason)
    return self.http:delete("/guilds/" .. guild_id .. "/stickers/" .. sticker_id, opts_with_reason(reason))
end

-- Interaction responses

function Route:create_interaction_response(interaction_id, interaction_token, payload, files)
    return self.http:post_interaction_callback(interaction_id, interaction_token, payload, files)
end

function Route:edit_interaction_response(application_id, interaction_token, payload, files)
    local endpoint = "/webhooks/" .. application_id .. "/" .. interaction_token .. "/messages/@original"
    if files and #files > 0 then
        return self.http:patch_multipart(endpoint, payload, files)
    end
    return self.http:patch(endpoint, payload)
end

function Route:get_original_interaction_response(application_id, interaction_token)
    return self.http:get("/webhooks/" .. application_id .. "/" .. interaction_token .. "/messages/@original")
end

function Route:delete_original_interaction_response(application_id, interaction_token)
    return self.http:delete("/webhooks/" .. application_id .. "/" .. interaction_token .. "/messages/@original")
end

function Route:create_followup_message(application_id, interaction_token, payload, files)
    local endpoint = "/webhooks/" .. application_id .. "/" .. interaction_token
    if files and #files > 0 then
        return self.http:post_multipart(endpoint, payload, files)
    end
    return self.http:post(endpoint, payload)
end

function Route:get_followup_message(application_id, interaction_token, message_id)
    return self.http:get("/webhooks/" .. application_id .. "/" .. interaction_token .. "/messages/" .. message_id)
end

function Route:edit_followup_message(application_id, interaction_token, message_id, payload, files)
    local endpoint = "/webhooks/" .. application_id .. "/" .. interaction_token .. "/messages/" .. message_id
    if files and #files > 0 then
        return self.http:patch_multipart(endpoint, payload, files)
    end
    return self.http:patch(endpoint, payload)
end

function Route:delete_followup_message(application_id, interaction_token, message_id)
    return self.http:delete("/webhooks/" .. application_id .. "/" .. interaction_token .. "/messages/" .. message_id)
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

-- Scheduled events

local function query_string(params)
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
    return query
end

function Route:get_guild_scheduled_events(guild_id, with_user_count)
    local query = query_string({ with_user_count = with_user_count and 1 or 0 })
    return self.http:get("/guilds/" .. guild_id .. "/scheduled-events" .. query)
end

function Route:get_guild_scheduled_event(guild_id, event_id, with_user_count)
    local query = query_string({ with_user_count = with_user_count and 1 or 0 })
    return self.http:get("/guilds/" .. guild_id .. "/scheduled-events/" .. event_id .. query)
end

function Route:create_guild_scheduled_event(guild_id, payload, reason)
    return self.http:post("/guilds/" .. guild_id .. "/scheduled-events", payload, opts_with_reason(reason))
end

-- AutoMod

function Route:get_auto_moderation_rules(guild_id)
    return self.http:get("/guilds/" .. guild_id .. "/auto-moderation/rules")
end

function Route:get_auto_moderation_rule(guild_id, rule_id)
    return self.http:get("/guilds/" .. guild_id .. "/auto-moderation/rules/" .. rule_id)
end

function Route:create_auto_moderation_rule(guild_id, payload, reason)
    return self.http:post("/guilds/" .. guild_id .. "/auto-moderation/rules", payload, opts_with_reason(reason))
end

-- Audit Log

function Route:get_audit_logs(guild_id, params)
    local query = query_string(params)
    return self.http:get("/guilds/" .. guild_id .. "/audit-logs" .. query)
end

-- Welcome Screen

function Route:get_welcome_screen(guild_id)
    return self.http:get("/guilds/" .. guild_id .. "/welcome-screen")
end

function Route:edit_welcome_screen(guild_id, payload, reason)
    return self.http:patch("/guilds/" .. guild_id .. "/welcome-screen", payload, opts_with_reason(reason))
end

-- Widget

function Route:get_widget(guild_id)
    return self.http:get("/guilds/" .. guild_id .. "/widget.json")
end

function Route:edit_widget(guild_id, payload)
    return self.http:patch("/guilds/" .. guild_id .. "/widget", payload)
end

-- Stage Instances

function Route:get_stage_instance(channel_id)
    return self.http:get("/stage-instances/" .. channel_id)
end

function Route:create_stage_instance(payload, reason)
    return self.http:post("/stage-instances", payload, opts_with_reason(reason))
end

function Route:edit_stage_instance(channel_id, payload, reason)
    return self.http:patch("/stage-instances/" .. channel_id, payload, opts_with_reason(reason))
end

function Route:delete_stage_instance(channel_id, reason)
    return self.http:delete("/stage-instances/" .. channel_id, opts_with_reason(reason))
end

-- Integrations

function Route:get_all_integrations(guild_id)
    return self.http:get("/guilds/" .. guild_id .. "/integrations")
end

function Route:edit_integration(guild_id, integration_id, payload)
    return self.http:patch("/guilds/" .. guild_id .. "/integrations/" .. integration_id, payload)
end

function Route:sync_integration(guild_id, integration_id)
    return self.http:post("/guilds/" .. guild_id .. "/integrations/" .. integration_id .. "/sync", {})
end

function Route:delete_integration(guild_id, integration_id, reason)
    return self.http:delete(
        "/guilds/" .. guild_id .. "/integrations/" .. integration_id,
        opts_with_reason(reason)
    )
end

-- Templates

function Route:get_template(code)
    return self.http:get("/guilds/templates/" .. code)
end

function Route:get_guild_templates(guild_id)
    return self.http:get("/guilds/" .. guild_id .. "/templates")
end

function Route:create_template(guild_id, payload)
    return self.http:post("/guilds/" .. guild_id .. "/templates", payload)
end

function Route:sync_template(guild_id, code)
    return self.http:put("/guilds/" .. guild_id .. "/templates/" .. code, {})
end

function Route:edit_template(guild_id, code, payload)
    return self.http:patch("/guilds/" .. guild_id .. "/templates/" .. code, payload)
end

function Route:delete_template(guild_id, code)
    return self.http:delete("/guilds/" .. guild_id .. "/templates/" .. code)
end

function Route:get_current_application()
    return self.http:get("/oauth2/applications/@me")
end

function Route:edit_current_application(payload)
    return self.http:patch("/applications/@me", payload)
end

function Route:get_application(application_id)
    return self.http:get("/applications/" .. application_id .. "/rpc")
end

function Route:get_application_role_connection_metadata(application_id)
    return self.http:get("/applications/" .. application_id .. "/role-connections/metadata")
end

function Route:update_application_role_connection_metadata(application_id, payload)
    return self.http:put("/applications/" .. application_id .. "/role-connections/metadata", payload)
end

function Route:get_skus(application_id)
    return self.http:get("/applications/" .. application_id .. "/skus")
end

function Route:get_entitlements(application_id, params)
    local parts = {}
    for key, value in pairs(params or {}) do
        if value ~= nil then
            if type(value) == "table" then value = table.concat(value, ",") end
            parts[#parts + 1] = key .. "=" .. tostring(value)
        end
    end
    local suffix = #parts > 0 and "?" .. table.concat(parts, "&") or ""
    return self.http:get("/applications/" .. application_id .. "/entitlements" .. suffix)
end

function Route:consume_entitlement(application_id, entitlement_id)
    return self.http:post("/applications/" .. application_id .. "/entitlements/" .. entitlement_id .. "/consume")
end

function Route:create_test_entitlement(application_id, payload)
    return self.http:post("/applications/" .. application_id .. "/entitlements", payload)
end

function Route:delete_test_entitlement(application_id, entitlement_id)
    return self.http:delete("/applications/" .. application_id .. "/entitlements/" .. entitlement_id)
end

function Route:get_sku_subscriptions(sku_id, params)
    local parts = {}
    for key, value in pairs(params or {}) do
        if value ~= nil then parts[#parts + 1] = key .. "=" .. tostring(value) end
    end
    local suffix = #parts > 0 and "?" .. table.concat(parts, "&") or ""
    return self.http:get("/skus/" .. sku_id .. "/subscriptions" .. suffix)
end

function Route:get_subscription(sku_id, subscription_id)
    return self.http:get("/skus/" .. sku_id .. "/subscriptions/" .. subscription_id)
end

function Route:get_onboarding(guild_id)
    return self.http:get("/guilds/" .. guild_id .. "/onboarding")
end

function Route:edit_onboarding(guild_id, payload, reason)
    return self.http:put("/guilds/" .. guild_id .. "/onboarding", payload, opts_with_reason(reason))
end

function Route:modify_guild_incident_actions(guild_id, payload, reason)
    return self.http:put("/guilds/" .. guild_id .. "/incident-actions", payload, opts_with_reason(reason))
end

return Route
