local Paginator = {}
Paginator.__index = Paginator

function Paginator.new(fetch_page, opts)
    if type(fetch_page) ~= "function" then
        error("Paginator requires a fetch_page function", 0)
    end
    opts = opts or {}
    return setmetatable({
        _fetch_page = fetch_page,
        _page_size = opts.page_size or 100,
        _remaining = opts.limit,
        _cursor_key = opts.cursor_key or "before",
        _cursor = opts.cursor,
        _done = false,
        _items = {},
        _extract = opts.extract or function(response) return response or {} end,
        _cursor_for = opts.cursor_for or function(item) return item.id end,
        _has_more = opts.has_more,
    }, Paginator)
end

function Paginator:next()
    while #self._items == 0 and not self._done do
        local page_size = self._page_size
        if self._remaining and self._remaining < page_size then
            page_size = self._remaining
        end
        if page_size <= 0 then
            self._done = true
            break
        end
        local params = { limit = page_size }
        if self._cursor then
            params[self._cursor_key] = self._cursor
        end
        local response = self._fetch_page(params)
        local items = self._extract(response)
        if #items == 0 then
            self._done = true
            break
        end
        for _, item in ipairs(items) do
            self._items[#self._items + 1] = item
        end
        self._cursor = self._cursor_for(items[#items])
        if #items < page_size or (self._has_more and not self._has_more(response)) then
            self._done = true
        end
    end
    local item = table.remove(self._items, 1)
    if item and self._remaining then
        self._remaining = self._remaining - 1
    end
    return item
end

function Paginator:iter()
    return function()
        return self:next()
    end
end

return Paginator
