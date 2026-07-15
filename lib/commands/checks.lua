-- lib/commands/checks.lua
-- Command checks for ext.commands
local permission = require("models.permission")
local M = {}
-- Helper to extract id from author (handles both string and table)
local function extract_id_from_author(ctx)
    local author = ctx.author
    if type(author) == "table" then
        if type(author.id) == "table" then
            return author.id.id or author.id.username or author.id.global_name
        end
        return author.id
    end
    return author
end
-- Helper to extract id from guild
local function extract_id_from_guild(ctx)
    local guild = ctx.guild
    if type(guild) == "table" then
        if type(guild.id) == "table" then
            return guild.id.id or guild.id.name
        end
        return guild.id
    end
    return guild
end
-- Helper to extract role_id from role_id (handles both string and table)
local function extract_role_id(role_id)
    if type(role_id) == "table" then
        return role_id.id or role_id.name
    end
    return role_id
end
-- Base check class
M.Check = function(name, fn)
    return {
        name = name,
        func = fn,
    }
end
-- Owner check
function M.owner(func)
    return M.Check("owner", function(ctx)
        local author_id = extract_id_from_author(ctx)
        local member = ctx.bot:get_member(author_id)
        return member and member.id == ctx.bot.owner_id
    end)
end
-- Admin check
function M.admin(func)
    return M.Check("admin", function(ctx)
        if not ctx.guild then
            return false
        end
        local author_id = extract_id_from_author(ctx)
        local member = ctx.bot:get_member(author_id)
        local member_roles = member and member.roles or ctx.author.roles or {}
        for _, role_id in ipairs(member_roles) do
            local role = ctx.bot:get_role(extract_role_id(role_id))
            if role then
                if role.admin or role.permissions and permission.has_permission(role.permissions, permission.ADMINISTRATOR) then
                    return true
                end
            end
        end
        return false
    end)
end
-- Staff check
function M.staff(func)
    return M.Check("staff", function(ctx)
        if not ctx.guild then
            return false
        end
        local author_id = extract_id_from_author(ctx)
        local member = ctx.bot:get_member(author_id)
        local member_roles = member and member.roles or ctx.author.roles or {}
        for _, role_id in ipairs(member_roles) do
            local role = ctx.bot:get_role(extract_role_id(role_id))
            if role then
                if role.staff or role.name == "Staff" then
                    return true
                end
            end
        end
        return false
    end)
end
-- Mod check
function M.mod(func)
    return M.Check("mod", function(ctx)
        if not ctx.guild then
            return false
        end
        local author_id = extract_id_from_author(ctx)
        local member = ctx.bot:get_member(author_id)
        local member_roles = member and member.roles or ctx.author.roles or {}
        for _, role_id in ipairs(member_roles) do
            local role = ctx.bot:get_role(extract_role_id(role_id))
            if role then
                if role.mod or role.name == "Mod" then
                    return true
                end
            end
        end
        return false
    end)
end
-- User check
function M.user(user_id, func)
    return M.Check("user", function(ctx)
        return extract_id_from_author(ctx) == user_id
    end)
end
-- Guild check
function M.guild(guild_id, func)
    return M.Check("guild", function(ctx)
        if not ctx.guild then
            return false
        end
        return extract_id_from_guild(ctx) == guild_id
    end)
end
-- Bot check
function M.bot(func)
    return M.Check("bot", function(ctx)
        if not ctx.bot then
            return false
        end
        return true
    end)
end
-- Raw check
function M.raw(func)
    return M.Check("raw", function()
        return true
    end)
end
return M
