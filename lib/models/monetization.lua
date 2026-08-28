local class = require("../core/class")

local function query(params)
    local parts = {}
    for key, value in pairs(params or {}) do
        if value ~= nil then
            if type(value) == "table" then value = table.concat(value, ",") end
            parts[#parts + 1] = key .. "=" .. tostring(value)
        end
    end
    return #parts > 0 and "?" .. table.concat(parts, "&") or ""
end

local Subscription

local SKU = class("SKU")
function SKU.new(data, http)
    data = data or {}
    local self = {
        id = data.id,
        type = data.type,
        application_id = data.application_id,
        name = data.name,
        slug = data.slug,
        flags = data.flags or 0,
        flag_set = require("./flags").SKUFlags.new(data.flags or 0),
        http = http,
    }
    setmetatable(self, { __index = SKU })
    return self
end

function SKU:url()
    return "https://discord.com/application-directory/" .. self.application_id .. "/store/" .. self.id
end

function SKU:fetch_subscriptions(opts)
    if not self.http then error("SKU has no http client attached, cannot fetch subscriptions", 0) end
    local Route = require("../http/route")
    local data = Route.new(self.http):get_sku_subscriptions(self.id, opts)
    local result = {}
    for index, item in ipairs(data or {}) do result[index] = Subscription.new(item, self.http) end
    return result
end

local Entitlement = class("Entitlement")
function Entitlement.new(data, http)
    data = data or {}
    local self = {
        id = data.id,
        sku_id = data.sku_id,
        application_id = data.application_id,
        user_id = data.user_id,
        type = data.type,
        deleted = data.deleted or false,
        starts_at = data.starts_at,
        ends_at = data.ends_at,
        guild_id = data.guild_id,
        consumed = data.consumed or false,
        http = http,
    }
    setmetatable(self, { __index = Entitlement })
    return self
end

function Entitlement:consume()
    if not self.http then error("Entitlement has no http client attached, cannot consume", 0) end
    local Route = require("../http/route")
    Route.new(self.http):consume_entitlement(self.application_id, self.id)
    self.consumed = true
end

function Entitlement:delete()
    if not self.http then error("Entitlement has no http client attached, cannot delete", 0) end
    local Route = require("../http/route")
    return Route.new(self.http):delete_test_entitlement(self.application_id, self.id)
end

Subscription = class("Subscription")
function Subscription.new(data, http)
    data = data or {}
    local self = {
        id = data.id,
        user_id = data.user_id,
        sku_ids = data.sku_ids or {},
        entitlement_ids = data.entitlement_ids or {},
        renewal_sku_ids = data.renewal_sku_ids or {},
        current_period_start = data.current_period_start,
        current_period_end = data.current_period_end,
        status = data.status,
        canceled_at = data.canceled_at,
        country = data.country,
        http = http,
    }
    setmetatable(self, { __index = Subscription })
    return self
end

return { SKU = SKU, Entitlement = Entitlement, Subscription = Subscription, query = query }
