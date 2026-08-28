local class = require("../core/class")
local User = require("./user")

local TeamMember = class("TeamMember")
function TeamMember.new(team, data)
    data = data or {}
    local self = User.new(data.user or data)
    self.team = team
    self.membership_state = data.membership_state
    self.role = data.role
    return self
end

local Team = class("Team")
function Team.new(data)
    data = data or {}
    local self = {
        id = data.id,
        name = data.name,
        icon = data.icon,
        owner_id = data.owner_user_id,
        members = {},
    }
    setmetatable(self, { __index = Team })
    for index, member in ipairs(data.members or {}) do
        self.members[index] = TeamMember.new(self, member)
    end
    return self
end

function Team:get_owner()
    for _, member in ipairs(self.members) do
        if member.id == self.owner_id then return member end
    end
    return nil
end

return { Team = Team, TeamMember = TeamMember }
