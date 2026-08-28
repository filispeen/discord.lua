local class = require("../core/class")

local Metadata = class("ApplicationRoleConnectionMetadata")
function Metadata.new(data)
    data = data or {}
    local self = {
        type = data.type,
        key = data.key,
        name = data.name,
        description = data.description,
        name_localizations = data.name_localizations,
        description_localizations = data.description_localizations,
    }
    setmetatable(self, { __index = Metadata })
    return self
end

function Metadata:to_dict()
    local result = {
        type = self.type,
        key = self.key,
        name = self.name,
        description = self.description,
    }
    if self.name_localizations ~= nil then result.name_localizations = self.name_localizations end
    if self.description_localizations ~= nil then result.description_localizations = self.description_localizations end
    return result
end

return Metadata
