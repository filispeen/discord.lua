local class = require("../core/class")

local PrimaryGuild = class("PrimaryGuild")
function PrimaryGuild.new(data)
    data = data or {}
    local self = {
        identity_guild_id = data.identity_guild_id,
        identity_enabled = data.identity_enabled,
        tag = data.tag,
        badge = data.badge,
    }
    setmetatable(self, { __index = PrimaryGuild })
    return self
end

function PrimaryGuild:equals(other)
    return other and self.identity_guild_id == other.identity_guild_id
        and self.identity_enabled == other.identity_enabled and self.tag == other.tag
end

return PrimaryGuild
