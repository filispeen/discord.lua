require("spec_helper")

local Guild = require("./models/guild")
local AuditLog = require("./models/audit_log")

describe("typed audit cache resolution", function()
    it("resolves cached role deltas", function()
        local client = {
            roles = {
                get = function(_, guild_id, role_id)
                    if guild_id == "g1" and role_id == "r1" then
                        return { id = "r1", name = "Moderators", color = 42 }
                    end
                end,
            },
        }
        local guild = { id = "g1", client = client }
        local entry = AuditLog.AuditLogEntry.new({
            changes = { { key = "$add", new_value = { { id = "r1", name = "old" } } } },
        }, guild, nil, client)

        assert.equals("Moderators", entry.changes.after.roles[1].name)
        assert.equals(42, entry.changes.after.roles[1].color)
    end)
end)

describe("Guild:iter_audit_logs", function()
    it("fetches audit pages lazily", function()
        local calls = 0
        local http = {
            get = function(_, endpoint)
                calls = calls + 1
                if endpoint:find("before=a2", 1, true) then
                    return { audit_log_entries = { { id = "a1" } } }
                end
                return { audit_log_entries = { { id = "a3" }, { id = "a2" } } }
            end,
        }
        local guild = Guild.new({ id = "g1" }, http)
        local ids = {}
        for entry in guild:iter_audit_logs({ page_size = 2, limit = 3 }) do
            ids[#ids + 1] = entry.id
        end

        assert.same({ "a3", "a2", "a1" }, ids)
        assert.equals(2, calls)
    end)
end)
