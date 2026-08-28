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
--     Message reactions, array of Reaction instances (see reaction.lua).
--
--   Message:add_reaction(emoji) -> table
--     PUT .../reactions/{emoji}/@me. emoji is a unicode emoji string, a
--     "name:id" custom emoji string, or a table with .name/.id (as
--     found on Reaction.emoji/gateway emoji payloads).
--
--   Message:remove_reaction(emoji, user_id?) -> table
--     DELETE .../reactions/{emoji}/{user_id}, or .../reactions/{emoji}/@me
--     when user_id is nil (mirrors pycord's remove_reaction/
--     remove_own_reaction split).
--
--   Message:clear_reaction(emoji) -> table
--     DELETE .../reactions/{emoji}. Removes every reaction for one emoji.
--
--   Message:clear_reactions() -> table
--     DELETE .../reactions. Removes every reaction from the message.
--
--   Message:_add_reaction(data, own_user_id) -> Reaction
--     Applies a MESSAGE_REACTION_ADD gateway payload to this message's
--     local .reactions list in place (mirrors pycord's internal
--     Message._add_reaction). Not wired automatically since discord.lua
--     has no message cache; call this yourself on a Message instance
--     you already hold if you want it to track its own reaction counts.
--
--   Message:_remove_reaction(data, own_user_id) -> Reaction or nil
--     Applies a MESSAGE_REACTION_REMOVE gateway payload, dropping the
--     Reaction once its count reaches 0.
--
--   Message:_clear_emoji(emoji) -> Reaction or nil
--     Applies a MESSAGE_REACTION_REMOVE_EMOJI gateway payload, removing
--     every reaction for that one emoji.
--
--   Message:_clear_reactions() -> table
--     Applies a MESSAGE_REACTION_REMOVE_ALL gateway payload, clearing
--     every reaction. Returns the previous reactions array.
--
--   Message:create_thread(opts) -> Thread
--     opts.name (required), opts.auto_archive_duration,
--     opts.slowmode_delay. POST /channels/{channel_id}/messages/{id}/threads,
--     always creates a public thread (mirrors pycord's Message.create_thread()).
--
--   Message:poll -> Poll or nil
--     Parsed Poll instance (see poll.lua) if this message has one,
--     with self.message already wired for Poll:end_poll().
--
--   Message:end_poll() -> table
--     POST /channels/{channel_id}/polls/{id}/expire. Errors if this
--     message has no poll.
--
--   Message:get_poll_answer_voters(answer_id, opts?) -> table
--     GET /channels/{channel_id}/polls/{id}/answers/{answer_id}.
--     opts.limit / opts.after: standard pagination, both optional.

local class = require("../core/class")
local Reaction = require("./reaction")
local Poll = require("./poll").Poll

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
    self.reactions = {}
    for _, reaction_data in ipairs(data.reactions or {}) do
        table.insert(self.reactions, Reaction.new(reaction_data))
    end

    if data.poll then
        self.poll = Poll.from_dict(data.poll, self)
    end
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

function Message:_copy()
    local copy = {}
    for key, value in pairs(self) do
        if key == "reactions" then
            copy.reactions = {}
            for index, reaction in ipairs(value) do
                local reaction_copy = {}
                for reaction_key, reaction_value in pairs(reaction) do
                    reaction_copy[reaction_key] = reaction_value
                end
                setmetatable(reaction_copy, getmetatable(reaction))
                copy.reactions[index] = reaction_copy
            end
        elseif key == "poll" and value then
            copy.poll = Poll.from_dict(value:to_dict(), copy)
        else
            copy[key] = value
        end
    end
    return setmetatable(copy, getmetatable(self))
end

function Message:_update(data)
    data = data or {}
    local fields = {
        "id", "author", "content", "channel_id", "guild_id", "mention_everyone",
        "tts", "mention_roles", "mention_channels", "mentions", "attachments",
        "embeds", "webhook_id", "type", "timestamp", "edited_timestamp", "pinned",
        "mention", "role_mentions",
    }
    for _, field in ipairs(fields) do
        if data[field] ~= nil then
            if field == "timestamp" or field == "edited_timestamp" then
                self[field] = tonumber(data[field])
            else
                self[field] = data[field]
            end
        end
    end
    if data.reactions ~= nil then
        self.reactions = {}
        for _, reaction_data in ipairs(data.reactions) do
            table.insert(self.reactions, Reaction.new(reaction_data))
        end
    end
    if data.poll ~= nil then
        self.poll = Poll.from_dict(data.poll, self)
    end
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

local function message_payload(content, opts)
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
    for key, value in pairs(opts or {}) do
        if key ~= "files" then
            payload[key] = value
        end
    end
    local files = (opts and opts.files) or (type(content) == "table" and content.files)
    return payload, files
end

function Message:reply(content, opts)
    if not self.http then
        error("Message has no http client attached, cannot reply")
    end
    local payload, files = message_payload(content, opts)
    local endpoint = "/channels/" .. self.channel_id .. "/messages"
    if files and #files > 0 then
        local Multipart = require("../http/multipart")
        return self.http:post_multipart(endpoint, Multipart.with_attachments(payload, files), files)
    end
    return self.http:post(endpoint, payload)
end

function Message:edit(content, opts)
    if not self.http then
        error("Message has no http client attached, cannot edit")
    end
    local payload, files = message_payload(content, opts)
    local endpoint = "/channels/" .. self.channel_id .. "/messages/" .. self.id
    if files and #files > 0 then
        local Multipart = require("../http/multipart")
        return self.http:patch_multipart(endpoint, Multipart.with_attachments(payload, files), files)
    end
    return self.http:patch(endpoint, payload)
end

-- Deletes this message via DELETE /channels/{channel_id}/messages/{id}.
function Message:delete()
    if not self.http then
        error("Message has no http client attached, cannot delete")
    end
    return self.http:delete("/channels/" .. self.channel_id .. "/messages/" .. self.id)
end

local function url_encode(str)
    return (str:gsub("[^%w%-%._~:]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

-- Normalizes an emoji argument to Discord's reaction path segment
-- format: "name" for unicode, "name:id" for custom. Accepts a raw
-- string (stripping surrounding <> like pycord's convert_emoji_reaction),
-- or a table with .name/.id (as found on Reaction.emoji/gateway payloads).
local function normalize_emoji(emoji)
    if type(emoji) == "table" then
        if emoji.id then
            return (emoji.name or "") .. ":" .. emoji.id
        end
        return tostring(emoji.name or emoji.emoji or emoji)
    end
    local s = tostring(emoji)
    return (s:gsub("^<", ""):gsub(">$", ""))
end

-- Adds a reaction to this message.
function Message:add_reaction(emoji)
    if not self.http then
        error("Message has no http client attached, cannot add_reaction")
    end
    local encoded = url_encode(normalize_emoji(emoji))
    return self.http:put("/channels/" .. self.channel_id .. "/messages/" .. self.id ..
        "/reactions/" .. encoded .. "/@me")
end

-- Removes a reaction from this message for the given user, or the bot
-- itself when user_id is nil.
function Message:remove_reaction(emoji, user_id)
    if not self.http then
        error("Message has no http client attached, cannot remove_reaction")
    end
    local encoded = url_encode(normalize_emoji(emoji))
    local target = user_id or "@me"
    return self.http:delete("/channels/" .. self.channel_id .. "/messages/" .. self.id ..
        "/reactions/" .. encoded .. "/" .. target)
end

-- Removes every reaction for one emoji from this message.
function Message:clear_reaction(emoji)
    if not self.http then
        error("Message has no http client attached, cannot clear_reaction")
    end
    local encoded = url_encode(normalize_emoji(emoji))
    return self.http:delete("/channels/" .. self.channel_id .. "/messages/" .. self.id ..
        "/reactions/" .. encoded)
end

-- Removes every reaction from this message.
function Message:clear_reactions()
    if not self.http then
        error("Message has no http client attached, cannot clear_reactions")
    end
    return self.http:delete("/channels/" .. self.channel_id .. "/messages/" .. self.id ..
        "/reactions")
end

function Message:_add_reaction(data, own_user_id)
    local key = Reaction.key(data.emoji)
    for _, r in ipairs(self.reactions) do
        if r.emoji_key == key then
            r.count = r.count + 1
            if data.user_id == own_user_id then
                r.me = true
            end
            return r
        end
    end
    local reaction = Reaction.new({
        emoji = data.emoji,
        count = 1,
        me = data.user_id == own_user_id,
    })
    table.insert(self.reactions, reaction)
    return reaction
end

function Message:_remove_reaction(data, own_user_id)
    local key = Reaction.key(data.emoji)
    for i, r in ipairs(self.reactions) do
        if r.emoji_key == key then
            r.count = r.count - 1
            if data.user_id == own_user_id then
                r.me = false
            end
            if r.count <= 0 then
                table.remove(self.reactions, i)
            end
            return r
        end
    end
    return nil
end

function Message:_clear_emoji(emoji)
    local key = Reaction.key(emoji)
    for i, r in ipairs(self.reactions) do
        if r.emoji_key == key then
            table.remove(self.reactions, i)
            return r
        end
    end
    return nil
end

function Message:_clear_reactions()
    local old = self.reactions
    self.reactions = {}
    return old
end

function Message:create_thread(opts)
    opts = opts or {}
    if not self.http then
        error("Message has no http client attached, cannot create_thread", 0)
    end
    if not opts.name then
        error("Message:create_thread() requires opts.name", 0)
    end

    local Thread = require("./thread")
    local payload = {
        name = opts.name,
        auto_archive_duration = opts.auto_archive_duration or 1440,
        rate_limit_per_user = opts.slowmode_delay or 0,
    }

    local endpoint = "/channels/" .. self.channel_id .. "/messages/" .. self.id .. "/threads"
    local created = self.http:post(endpoint, payload)
    return Thread.new(created, nil, self.http)
end

function Message:end_poll()
    if not self.http then
        error("Message has no http client attached, cannot end_poll", 0)
    end
    if not self.poll then
        error("This message has no poll to end", 0)
    end
    return self.http:post("/channels/" .. self.channel_id .. "/polls/" .. self.id .. "/expire")
end

function Message:get_poll_answer_voters(answer_id, opts)
    opts = opts or {}
    if not self.http then
        error("Message has no http client attached, cannot get_poll_answer_voters", 0)
    end

    local parts = {}
    if opts.limit then
        table.insert(parts, "limit=" .. tostring(opts.limit))
    end
    if opts.after then
        table.insert(parts, "after=" .. tostring(opts.after))
    end
    local query = #parts > 0 and ("?" .. table.concat(parts, "&")) or ""

    return self.http:get("/channels/" .. self.channel_id .. "/polls/" .. self.id ..
        "/answers/" .. answer_id .. query)
end

return Message
