-- lib/models/message.lua
-- Message model for Discord API
--
-- Public Contract:
--   Message.new(data) -> Message
--     Creates a new Message from API data.
--
--   Message:id -> string
--     Message's unique ID.
--
--   Message:author -> User
--     Message author.
--
--   Message:content -> string
--     Message content.
--
--   Message:channel_id -> string
--     Channel ID.
--
--   Message:guild_id -> string or nil
--     Guild ID (nil for DMs).
--
--   Message:timestamp -> number
--     Message timestamp.
--
--   Message:edited_timestamp -> number or nil
--     Edited timestamp (nil if not edited).
--
--   Message:embeds -> table
--     Message embeds.
--
--   Message:attachments -> table
--     Message attachments.
--
--   Message:reactions -> table
--     Message reactions.

local class = require("core.class")

-- Message class
local Message = class("Message")

function Message.new(data, http)
    local self = {}
    setmetatable(self, {
        __index = Message
    })

    self.id = data.id
    self.author = data.author
    self.content = data.content or ""
    self.channel_id = data.channel_id
    self.guild_id = data.guild_id
    self.mention_everyone = data.mention_everyone or false
    self.tts = data.tts or false
    self.mention_roles = data.mention_roles or {}
    self.mention_channels = data.mention_channels or {}
    self.mentions = data.mentions or {}
    self.attachments = data.attachments or {}
    self.embeds = data.embeds or {}
    self.reactions = data.reactions or {}
    self.webhook_id = data.webhook_id or nil
    self.type = data.type or "DEFAULT"

    -- Timestamps
    self.timestamp = data.timestamp and tonumber(data.timestamp)
    self.edited_timestamp = data.edited_timestamp and tonumber(data.edited_timestamp)

    -- Other fields
    self.pinned = data.pinned or false
    self.mention = data.mention or false
    self.role_mentions = data.role_mentions or {}

    self.http = http

    return self
end

-- Check if message mentions a specific user
function Message:mentions_user(user_id)
    for _, m in ipairs(self.mentions or {}) do
        if m.id == user_id then
            return true
        end
    end
    return false
end

-- Check if message mentions a specific role
function Message:mentions_role(role_id)
    for _, r in ipairs(self.mention_roles or {}) do
        if r == role_id then
            return true
        end
    end
    return false
end

-- Sends a new message to the same channel, mirrors pycord Message.reply
-- (as a plain channel send, discord.lua has no reply-reference field yet).
function Message:reply(content)
    if not self.http then
        error("Message has no http client attached, cannot reply")
    end
    local payload = type(content) == "table" and content or { content = content }
    return self.http:post("/channels/" .. self.channel_id .. "/messages", payload)
end

-- Edits this message's content via PATCH /channels/{channel_id}/messages/{id}.
function Message:edit(content)
    if not self.http then
        error("Message has no http client attached, cannot edit")
    end
    local payload = type(content) == "table" and content or { content = content }
    return self.http:patch("/channels/" .. self.channel_id .. "/messages/" .. self.id, payload)
end

-- Deletes this message via DELETE /channels/{channel_id}/messages/{id}.
function Message:delete()
    if not self.http then
        error("Message has no http client attached, cannot delete")
    end
    return self.http:delete("/channels/" .. self.channel_id .. "/messages/" .. self.id)
end

return Message
