-- lib/models/webhook.lua
-- Webhook model for Discord API
--
-- Public Contract:
--   Webhook.new(data) -> Webhook
--     Creates a new Webhook from API data.
--
--   Webhook:id -> string
--     Webhook's unique ID.
--
--   Webhook:name -> string
--     Webhook name.
--
--   Webhook:guild_id -> string or nil
--     Guild ID.
--
--   Webhook:channel_id -> string
--     Channel ID.
--
--   Webhook:token -> string or nil
--     Webhook token (sensitive, not sent via API).
--
--   Webhook:user -> User or nil
--     Webhook creator.
--
--   Webhook:avatar -> string or nil
--     Webhook avatar URL.
--
--   Webhook:application_id -> string or nil
--     Application ID.
--
--   Webhook:send(content, options) -> table
--     Sends a message via webhook.

local class = require("../core/class")
local json = require("../core/json_compat")

-- Webhook class
local Webhook = class("Webhook")

function Webhook.new(data, http)
    local self = {}
    setmetatable(self, {
        __index = Webhook
    })

    self.id = data.id
    self.name = data.name
    self.guild_id = data.guild_id
    self.channel_id = data.channel_id
    self.token = data.token
    self.user = data.user
    self.avatar = data.avatar or nil
    self.application_id = data.application_id or nil
    self.http = http

    return self
end

function Webhook.fetch(webhook_id, http, webhook_token)
    if not http then
        error("Webhook.fetch requires an http client", 0)
    end
    local Route = require("../http/route")
    local route = Route.new(http)
    local data
    if webhook_token then
        data = route:get_webhook_with_token(webhook_id, webhook_token)
    else
        data = route:get_webhook(webhook_id)
    end
    return Webhook.new(data, http)
end

function Webhook:edit(opts)
    opts = opts or {}
    if not self.http then
        error("Webhook has no http client attached, cannot edit", 0)
    end
    local payload = {}
    if opts.name ~= nil then
        payload.name = opts.name
    end
    if opts.avatar ~= nil then
        payload.avatar = opts.avatar
    end
    local Route = require("../http/route")
    local data = Route.new(self.http):edit_webhook(self.id, payload, opts.reason)
    for key, value in pairs(data or {}) do
        self[key] = value
    end
    return self
end

function Webhook:delete(reason)
    if not self.http then
        error("Webhook has no http client attached, cannot delete", 0)
    end
    local Route = require("../http/route")
    return Route.new(self.http):delete_webhook(self.id, reason)
end

function Webhook:send(content, opts)
    if not self.token then
        error("Webhook token not available", 0)
    end
    if not self.http then
        error("Webhook has no http client attached, cannot send", 0)
    end
    opts = opts or {}
    local payload = {}
    if type(content) == "table" then
        for key, value in pairs(content) do
            if key ~= "files" then
                payload[key] = value
            end
        end
    else
        payload.content = content
    end
    for key, value in pairs(opts) do
        if key ~= "files" then
            payload[key] = value
        end
    end
    local files = opts.files or (type(content) == "table" and content.files)
    local endpoint = "/webhooks/" .. self.id .. "/" .. self.token
    if files and #files > 0 then
        local Multipart = require("../http/multipart")
        return self.http:post_multipart(endpoint, Multipart.with_attachments(payload, files), files)
    end
    return self.http:post(endpoint, payload)
end

return Webhook
