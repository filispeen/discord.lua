-- spec/models/audit_log_spec.lua
-- Tests for Audit Log models

require("spec_helper")

local AuditLog = require("./models/audit_log")
local AuditLogEntry = AuditLog.AuditLogEntry
local AuditLogChanges = AuditLog.AuditLogChanges

local function entry_payload()
    return {
        id = "1",
        guild_id = "g1",
        action_type = 20,
        user_id = "mod1",
        target_id = "target1",
        reason = "spam",
        options = { count = "3" },
        changes = {
            { key = "name", old_value = "old-name", new_value = "new-name" },
        },
    }
end

describe("AuditLogChanges", function()
    it("builds before/after from raw old_value/new_value pairs", function()
        local changes = AuditLogChanges.new({
            { key = "name", old_value = "old", new_value = "new" },
        })

        assert.equals("old", changes.before.name)
        assert.equals("new", changes.after.name)
    end)

    it("handles a change with only old_value", function()
        local changes = AuditLogChanges.new({
            { key = "nsfw", old_value = true },
        })

        assert.is_true(changes.before.nsfw)
        assert.is_nil(changes.after.nsfw)
    end)

    it("handles a change with only new_value", function()
        local changes = AuditLogChanges.new({
            { key = "nsfw", new_value = true },
        })

        assert.is_nil(changes.before.nsfw)
        assert.is_true(changes.after.nsfw)
    end)

    it("populates after.roles on $add and ensures before.roles defaults to empty", function()
        local changes = AuditLogChanges.new({
            { key = "$add", new_value = { { id = "r1", name = "Muted" } } },
        })

        assert.same({}, changes.before.roles)
        assert.equals("r1", changes.after.roles[1].id)
        assert.equals("Muted", changes.after.roles[1].name)
    end)

    it("populates before.roles on $remove and ensures after.roles defaults to empty", function()
        local changes = AuditLogChanges.new({
            { key = "$remove", new_value = { { id = "r2", name = "VIP" } } },
        })

        assert.same({}, changes.after.roles)
        assert.equals("r2", changes.before.roles[1].id)
        assert.equals("VIP", changes.before.roles[1].name)
    end)

    it("returns empty before/after tables when there are no changes", function()
        local changes = AuditLogChanges.new()

        assert.same({}, changes.before)
        assert.same({}, changes.after)
    end)
end)

describe("AuditLogEntry", function()
    it("reads core fields from the payload", function()
        local entry = AuditLogEntry.new(entry_payload())

        assert.equals("1", entry.id)
        assert.equals("g1", entry.guild_id)
        assert.equals(20, entry.action_type)
        assert.equals("mod1", entry.user_id)
        assert.equals("target1", entry.target_id)
        assert.equals("spam", entry.reason)
        assert.equals("3", entry.extra.count)
    end)

    it("builds changes from the payload's changes array", function()
        local entry = AuditLogEntry.new(entry_payload())

        assert.equals("old-name", entry.changes.before.name)
        assert.equals("new-name", entry.changes.after.name)
    end)

    it("falls back to guild.id when the payload has no guild_id", function()
        local data = entry_payload()
        data.guild_id = nil
        local guild = { id = "g2" }

        local entry = AuditLogEntry.new(data, guild)
        assert.equals("g2", entry.guild_id)
        assert.equals(guild, entry.guild)
    end)

    it("falls back to guild.http when no http is given directly", function()
        local guild = { id = "g2", http = {} }
        local entry = AuditLogEntry.new(entry_payload(), guild)
        assert.equals(guild.http, entry.http)
    end)

    it("handles a payload with no changes or options", function()
        local entry = AuditLogEntry.new({ id = "1", guild_id = "g1", action_type = 1 })

        assert.is_nil(entry.extra)
        assert.same({}, entry.changes.before)
        assert.same({}, entry.changes.after)
    end)
end)
