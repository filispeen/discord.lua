-- spec/commands/checks_spec.lua
-- Tests for checks

-- Setup package path to find lib modules
package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local M = require("commands.checks")

describe("Checks", function()
    describe("owner check", function()
        it("returns true for owner", function()
            local mock_ctx = {
                author = { id = "123" },
                bot = { owner_id = "123", get_member = function() return { id = "123" } end }
            }

            local check = M.owner(function(ctx) return true end)
            assert.is_true(check.func(mock_ctx))
        end)

        it("returns false for non-owner", function()
            local mock_ctx = {
                author = { id = "456" },
                bot = { owner_id = "123", get_member = function() return { id = "456" } end }
            }

            local check = M.owner(function(ctx) return true end)
            assert.is_false(check.func(mock_ctx))
        end)
    end)

    describe("admin check", function()
        it("returns true for admin role", function()
            local mock_ctx = {
                author = { id = "123", roles = { "789" } },
                guild = { id = "111" },
                bot = { get_member = function() return { id = "123" } end, get_role = function(id)
                    if id == "789" then return { admin = true } end
                    return nil
                end }
            }

            local check = M.admin(function(ctx) return true end)
            assert.is_true(check.func(mock_ctx))
        end)

        it("returns false for non-admin", function()
            local mock_ctx = {
                author = { id = "123", roles = { "789" } },
                guild = { id = "111" },
                bot = { get_member = function() return { id = "123" } end, get_role = function(id)
                    if id == "789" then return { admin = false } end
                    return nil
                end }
            }

            local check = M.admin(function(ctx) return true end)
            assert.is_false(check.func(mock_ctx))
        end)
    end)

    describe("staff check", function()
        it("returns true for staff role", function()
            local mock_ctx = {
                author = { id = "123", roles = { "789" } },
                guild = { id = "111" },
                bot = { get_member = function() return { id = "123" } end, get_role = function(id)
                    if id == "789" then return { staff = true } end
                    return nil
                end }
            }

            local check = M.staff(function(ctx) return true end)
            assert.is_true(check.func(mock_ctx))
        end)
    end)

    describe("mod check", function()
        it("returns true for mod role", function()
            local mock_ctx = {
                author = { id = "123", roles = { "789" } },
                guild = { id = "111" },
                bot = { get_member = function() return { id = "123" } end, get_role = function(id)
                    if id == "789" then return { mod = true } end
                    return nil
                end }
            }

            local check = M.mod(function(ctx) return true end)
            assert.is_true(check.func(mock_ctx))
        end)
    end)

    describe("user check", function()
        it("returns true for specific user", function()
            local mock_ctx = {
                author = { id = "123" }
            }

            local check = M.user("123", function(ctx) return true end)
            assert.is_true(check.func(mock_ctx))
        end)

        it("returns false for different user", function()
            local mock_ctx = {
                author = { id = "456" }
            }

            local check = M.user("123", function(ctx) return true end)
            assert.is_false(check.func(mock_ctx))
        end)
    end)

    describe("guild check", function()
        it("returns true for specific guild", function()
            local mock_ctx = {
                guild = { id = "123" }
            }

            local check = M.guild("123", function(ctx) return true end)
            assert.is_true(check.func(mock_ctx))
        end)

        it("returns false for different guild", function()
            local mock_ctx = {
                guild = { id = "456" }
            }

            local check = M.guild("123", function(ctx) return true end)
            assert.is_false(check.func(mock_ctx))
        end)

        it("returns false when no guild", function()
            local mock_ctx = {
                author = { id = "123" }
            }

            local check = M.guild("123", function(ctx) return true end)
            assert.is_false(check.func(mock_ctx))
        end)
    end)

    describe("bot check", function()
        it("returns true for specific bot", function()
            local mock_ctx = {
                guild = { id = "123" }
            }

            local check = M.bot(function(ctx) return true end)
            assert.is_true(check.func(mock_ctx))
        end)
    end)
end)
