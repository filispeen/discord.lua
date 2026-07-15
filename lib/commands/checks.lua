-- lib/commands/checks.lua
-- Command checks for ext.commands
--
-- Checks are functions that return true/false to allow/block command execution.

local M = {}

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
        local member = ctx.bot:get_member(ctx.author.id)
        return member and member.id == ctx.bot.owner_id
    end)
end

-- Admin check
function M.admin(func)
    return M.Check("admin", function(ctx)
        local guild = ctx.guild
        local member = ctx.bot:get_member(ctx.author.id)
        if not guild or not member then
            return false
        end

        -- Check if role is admin
        for _, role_id in ipairs(ctx.author.roles or {}) do
            local role = ctx.bot:get_role(role_id)
            if role and role.admin then
                return true
            end
        end
        return false
    end)
end

-- Staff check
function M.staff(func)
    return M.Check("staff", function(ctx)
        local guild = ctx.guild
        local member = ctx.bot:get_member(ctx.author.id)
        if not guild or not member then
            return false
        end

        -- Check if role is staff
        for _, role_id in ipairs(ctx.author.roles or {}) do
            local role = ctx.bot:get_role(role_id)
            if role and role.staff then
                return true
            end
        end
        return false
    end)
end

-- Mod check
function M.mod(func)
    return M.Check("mod", function(ctx)
        local guild = ctx.guild
        local member = ctx.bot:get_member(ctx.author.id)
        if not guild or not member then
            return false
        end

        -- Check if role is mod
        for _, role_id in ipairs(ctx.author.roles or {}) do
            local role = ctx.bot:get_role(role_id)
            if role and role.mod then
                return true
            end
        end
        return false
    end)
end

-- User check - only allow specific user
function M.user(user_id, func)
    return M.Check("user", function(ctx)
        return ctx.author.id == user_id
    end)
end

-- Guild check - only allow in specific guild
function M.guild(guild_id, func)
    return M.Check("guild", function(ctx)
        return ctx.guild and ctx.guild.id == guild_id
    end)
end

-- Bot check - only allow specific bot
function M.bot(func)
    return M.Check("bot", function(ctx)
        return ctx.bot.id == ctx.bot.id
    end)
end

-- Raw check - always passes
function M.raw(func)
    return M.Check("raw", function()
        return true
    end)
end

return M
