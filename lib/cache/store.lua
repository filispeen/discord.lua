-- lib/cache/store.lua
-- LRU Cache Store

local function create_cache(max_entries)
    local cache = {
        max_entries = max_entries or 100,
        entries = {},
        order = {},
    }

    local function remove_from_order(key)
        for i = 1, #cache.order do
            if cache.order[i] == key then
                table.remove(cache.order, i)
                break
            end
        end
    end

    function cache.size()
        return #cache.order
    end

    function cache.get(key)
        local entry = cache.entries[key]
        if not entry then
            return nil
        end
        remove_from_order(key)
        table.insert(cache.order, key)
        return entry.value
    end

    function cache.put(key, value)
        if cache.entries[key] then
            cache.entries[key].value = value
            remove_from_order(key)
            table.insert(cache.order, key)
            return
        end
        while #cache.order >= cache.max_entries do
            local old_key = table.remove(cache.order, 1)
            cache.entries[old_key] = nil
        end
        table.insert(cache.order, key)
        cache.entries[key] = {value = value}
    end

    function cache.remove(key)
        if cache.entries[key] then
            remove_from_order(key)
            cache.entries[key] = nil
            return true
        end
        return false
    end

    function cache.clear()
        cache.order = {}
        cache.entries = {}
    end

    function cache.is_full()
        return #cache.order >= cache.max_entries
    end

    function cache.has(key)
        return cache.entries[key] ~= nil
    end

    return cache
end

return create_cache