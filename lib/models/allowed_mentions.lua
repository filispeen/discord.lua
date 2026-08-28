local class = require("../core/class")

local DEFAULT = {}

local AllowedMentions = class("AllowedMentions")

local function option(opts, name)
    if opts[name] == nil then return DEFAULT end
    return opts[name]
end

local function ids(values)
    local result = {}
    for index, value in ipairs(values) do result[index] = type(value) == "table" and value.id or value end
    return result
end

function AllowedMentions.new(opts)
    opts = opts or {}
    local self = {
        everyone = option(opts, "everyone"),
        users = option(opts, "users"),
        roles = option(opts, "roles"),
        replied_user = option(opts, "replied_user"),
    }
    setmetatable(self, { __index = AllowedMentions })
    return self
end

function AllowedMentions.all()
    return AllowedMentions.new({ everyone = true, users = true, roles = true, replied_user = true })
end

function AllowedMentions.none()
    return AllowedMentions.new({ everyone = false, users = false, roles = false, replied_user = false })
end

function AllowedMentions:to_dict()
    local parse, data = {}, {}
    if self.everyone == true or self.everyone == DEFAULT then parse[#parse + 1] = "everyone" end
    if self.users == true or self.users == DEFAULT then parse[#parse + 1] = "users"
    elseif self.users ~= false then data.users = ids(self.users) end
    if self.roles == true or self.roles == DEFAULT then parse[#parse + 1] = "roles"
    elseif self.roles ~= false then data.roles = ids(self.roles) end
    if self.replied_user == true or self.replied_user == DEFAULT then data.replied_user = true end
    data.parse = parse
    return data
end

function AllowedMentions:merge(other)
    other = other or AllowedMentions.new()
    local function choose(name)
        if other[name] == DEFAULT then return self[name] end
        return other[name]
    end
    local result = AllowedMentions.new()
    result.everyone, result.users, result.roles, result.replied_user = choose("everyone"), choose("users"), choose("roles"), choose("replied_user")
    return result
end

AllowedMentions.DEFAULT = DEFAULT
return AllowedMentions
