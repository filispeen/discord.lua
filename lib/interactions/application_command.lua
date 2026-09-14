-- lib/interactions/application_command.lua
-- Application command model and Discord API v10 serializer.

local class = require("../core/class")

local ApplicationCommand = class("ApplicationCommand")

local function validate_options(options)
    if options == nil then return {} end
    if type(options) ~= "table" then
        error("ApplicationCommand options must be an array of option tables", 0)
    end
    local count, max_index = 0, 0
    for key in pairs(options) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
            error("ApplicationCommand options must be an array: { { name = ..., type = ... } }", 0)
        end
        count, max_index = count + 1, math.max(max_index, key)
    end
    if count ~= max_index then error("ApplicationCommand options must not have gaps", 0) end
    for index, option in ipairs(options) do
        if type(option) ~= "table" or type(option.name) ~= "string" or option.name == ""
            or type(option.type) ~= "number" then
            error("ApplicationCommand option #" .. index .. " requires string name and numeric type", 0)
        end
    end
    return options
end

local option_fields = {
    "type", "name", "name_localizations", "description", "description_localizations",
    "required", "choices", "autocomplete", "channel_types", "min_value", "max_value",
    "min_length", "max_length",
}

local function option_to_dict(option)
    local result = {}
    for _, field in ipairs(option_fields) do
        if option[field] ~= nil then result[field] = option[field] end
    end
    if option.options then
        result.options = {}
        for index, child in ipairs(option.options) do result.options[index] = option_to_dict(child) end
    end
    return result
end

ApplicationCommand.TYPE_CHAT_INPUT = 1
ApplicationCommand.TYPE_USER = 2
ApplicationCommand.TYPE_MESSAGE = 3

function ApplicationCommand.new(name, description, options)
    local self = setmetatable({}, { __index = ApplicationCommand })
    self.id = ""
    self.name = name
    self.description = description
    self.options = validate_options(options)
    self.aliases = {}
    self.type = ApplicationCommand.TYPE_CHAT_INPUT
    self.guild_ids = nil
    self.autocomplete_callbacks = {}
    self.callback = nil
    return self
end

function ApplicationCommand.from_dict(data)
    local self = ApplicationCommand.new(data.name, data.description, data.options)
    for _, field in ipairs({
        "id", "application_id", "guild_id", "type", "name_localizations",
        "description_localizations", "default_member_permissions", "integration_types",
        "contexts", "nsfw", "handler", "version",
    }) do
        self[field] = data[field]
    end
    if data.guild_id then self.guild_ids = { data.guild_id } end
    return self
end

function ApplicationCommand:set_autocomplete(option_name, callback)
    self.autocomplete_callbacks[option_name] = callback
    return self
end

function ApplicationCommand:to_dict()
    local dict = { name = self.name, description = self.description, type = self.type }
    if self.type == ApplicationCommand.TYPE_CHAT_INPUT and self.options and #self.options > 0 then
        dict.options = {}
        for index, option in ipairs(self.options) do
            dict.options[index] = option_to_dict(option)
            if self.autocomplete_callbacks[option.name] then dict.options[index].autocomplete = true end
        end
    end
    for _, field in ipairs({
        "name_localizations", "description_localizations", "integration_types", "contexts",
        "nsfw", "handler",
    }) do
        if self[field] ~= nil then dict[field] = self[field] end
    end
    if self.default_member_permissions ~= nil then
        dict.default_member_permissions = tostring(self.default_member_permissions)
    end
    return dict
end

function ApplicationCommand:add_alias(alias)
    table.insert(self.aliases, alias)
    return self
end

function ApplicationCommand:get_all_names()
    local names = { self.name }
    for _, alias in ipairs(self.aliases) do table.insert(names, alias) end
    return names
end

function ApplicationCommand:matches(input)
    for _, name in ipairs(self:get_all_names()) do
        if input:lower():find(name:lower(), 1, true) then return true end
    end
    return false
end

function ApplicationCommand:exact_match(input)
    input = input:lower()
    for _, name in ipairs(self:get_all_names()) do
        if name:lower() == input then return true end
    end
    return false
end

function ApplicationCommand.get_response_type(_self)
    return "APPLICATION_COMMAND_RESPONSE"
end

return ApplicationCommand
