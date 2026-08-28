local class = require("../core/class")

local IncidentsData = class("IncidentsData")
function IncidentsData.new(data)
    data = data or {}
    local self = {
        invites_disabled_until = data.invites_disabled_until,
        dms_disabled_until = data.dms_disabled_until,
        dm_spam_detected_at = data.dm_spam_detected_at,
        raid_detected_at = data.raid_detected_at,
    }
    setmetatable(self, { __index = IncidentsData })
    return self
end

function IncidentsData:to_dict()
    return {
        invites_disabled_until = self.invites_disabled_until,
        dms_disabled_until = self.dms_disabled_until,
        dm_spam_detected_at = self.dm_spam_detected_at,
        raid_detected_at = self.raid_detected_at,
    }
end

return IncidentsData
