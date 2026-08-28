local create_cache = require("./store")

local MessageStore = {}
MessageStore.__index = MessageStore

local function key(channel_id, message_id)
    return tostring(channel_id) .. ":" .. tostring(message_id)
end

function MessageStore.new(max_entries)
    return setmetatable({
        cache = create_cache(max_entries or 10000),
    }, MessageStore)
end

function MessageStore:put(message)
    if not message or not message.channel_id or not message.id then
        return
    end
    self.cache.put(key(message.channel_id, message.id), message)
end

function MessageStore:get(channel_id, message_id)
    if not channel_id or not message_id then
        return nil
    end
    return self.cache.get(key(channel_id, message_id))
end

function MessageStore:remove(channel_id, message_id)
    if not channel_id or not message_id then
        return
    end
    self.cache.remove(key(channel_id, message_id))
end

function MessageStore:remove_many(channel_id, message_ids)
    if not channel_id or not message_ids then
        return
    end
    for _, message_id in ipairs(message_ids) do
        self:remove(channel_id, message_id)
    end
end

return MessageStore
