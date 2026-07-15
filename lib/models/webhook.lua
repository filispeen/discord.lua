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

local class = require("core.class")
local json = require("json") or require("dkjson")

-- Webhook class
local Webhook = class("Webhook")

function Webhook.new(data)
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

    return self
end

-- Send a message via webhook
function Webhook:send(content, options)
    if not self.token then
        error("Webhook token not available", 0)
    end

    local headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. self.token,
    }

    local url = "https://discord.com/api/v10/webhooks/" .. self.id
    local http = require("http.client")
    local response, err = http.request(url, {
        method = "POST",
        headers = headers,
        body = json.encode({ content = content, options = options }),
    })

    if not response then
        error("Webhook send failed: " .. tostring(err), 0)
    end

    return json.decode(response.body) or {}
end

return Webhook
