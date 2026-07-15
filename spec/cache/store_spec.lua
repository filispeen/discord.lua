-- spec/cache/store_spec.lua
-- Tests for cache store

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

package.loaded["luv"] = {
    timer = {
        new = function()
            return {
                start = function() end,
                stop = function() end,
            }
        end
    },
    now = function() return 0 end
}

local Cache = require("lib.cache.store")

describe("Cache Store", function()
    it("creates a new cache", function()
        local cache = Cache(10)
        assert.equals(10, cache.max_entries)
        assert.equals(0, cache.size())
        assert.is_false(cache.is_full())
    end)

    it("adds entries", function()
        local cache = Cache(10)
        cache.put("key1", "value1")
        cache.put("key2", "value2")

        assert.equals(2, cache.size())
        assert.equals("value1", cache.get("key1"))
        assert.equals("value2", cache.get("key2"))
    end)

    it("evicts oldest entries when full", function()
        local cache = Cache(2)
        cache.put("key1", "value1")
        cache.put("key2", "value2")
        cache.put("key3", "value3")

        assert.equals(2, cache.size())
        assert.is_nil(cache.get("key1"))
        assert.equals("value2", cache.get("key2"))
        assert.equals("value3", cache.get("key3"))
    end)

    it("updates position on get", function()
        local cache = Cache(2)
        cache.put("key1", "value1")
        cache.put("key2", "value2")
        cache.put("key3", "value3")

        cache.get("key2")
        cache.put("key4", "value4")

        assert.equals(2, cache.size())
        assert.is_nil(cache.get("key1"))
        assert.equals("value2", cache.get("key2"))
        assert.equals("value4", cache.get("key4"))
    end)

    it("removes entries", function()
        local cache = Cache(10)
        cache.put("key1", "value1")
        cache.put("key2", "value2")

        cache.remove("key1")

        assert.equals(1, cache.size())
        assert.is_nil(cache.get("key1"))
        assert.equals("value2", cache.get("key2"))
    end)

    it("clears all entries", function()
        local cache = Cache(10)
        cache.put("key1", "value1")
        cache.put("key2", "value2")

        cache.clear()

        assert.equals(0, cache.size())
        assert.is_nil(cache.get("key1"))
        assert.is_nil(cache.get("key2"))
    end)

    it("has method works", function()
        local cache = Cache(10)
        cache.put("key1", "value1")

        assert.is_true(cache.has("key1"))
        assert.is_false(cache.has("key2"))
    end)
end)