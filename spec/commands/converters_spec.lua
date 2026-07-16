-- spec/commands/converters_spec.lua
-- Tests for converters

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local M = require("commands.converters")

describe("Converters", function()
    describe("StringConverter", function()
        it("converts string to string", function()
            local converter = M.StringConverter

            assert.equals("hello", converter.convert({}, "hello"))
            assert.equals("", converter.convert({}, ""))
        end)
    end)

    describe("IntegerConverter", function()
        it("converts string to integer", function()
            local converter = M.IntegerConverter

            assert.equals(42, converter.convert({}, "42"))
            assert.equals(0, converter.convert({}, "0"))
        end)

        it("throws error on invalid input", function()
            local converter = M.IntegerConverter

            assert.error(function()
                converter.convert({}, "not a number")
            end)
        end)
    end)

    describe("BooleanConverter", function()
        it("converts true/false strings", function()
            local converter = M.BooleanConverter

            assert.is_true(converter.convert({}, "true"))
            assert.is_true(converter.convert({}, "True"))
            assert.is_true(converter.convert({}, "TRUE"))
            assert.is_false(converter.convert({}, "false"))
            assert.is_false(converter.convert({}, "False"))
            assert.is_false(converter.convert({}, "FALSE"))
        end)

        it("throws error on invalid input", function()
            local converter = M.BooleanConverter

            assert.error(function()
                converter.convert({}, "yes")
            end)
        end)
    end)

    describe("UserConverter", function()
        it("converts user mention", function()
            local converter = M.UserConverter

            local result = converter.convert(
                { get_user = function(self, user_id) return { id = user_id, username = "Test" } end },
                "<@123456>"
            )
            assert.equals("123456", result.id)
            assert.equals("Test", result.username)
        end)

        it("converts user ID", function()
            local converter = M.UserConverter

            local result = converter.convert(
                { get_user = function(self, user_id) return { id = user_id, username = "Test" } end },
                "123456"
            )
            assert.equals("123456", result.id)
            assert.equals("Test", result.username)
        end)
    end)

    describe("MemberConverter", function()
        it("converts member mention", function()
            local converter = M.MemberConverter

            local result = converter.convert(
                { get_member = function(self, member_id) return { user = { id = member_id }, roles = { "111" } } end },
                "<@123456>"
            )
            assert.equals("123456", result.user.id)
            assert.equals(1, #result.roles)
        end)

        it("converts member ID", function()
            local converter = M.MemberConverter

            local result = converter.convert(
                { get_member = function(self, member_id) return { user = { id = member_id }, roles = { "111" } } end },
                "123456"
            )
            assert.equals("123456", result.user.id)
            assert.equals(1, #result.roles)
        end)
    end)

    describe("RoleConverter", function()
        it("converts role mention", function()
            local converter = M.RoleConverter

            local result = converter.convert(
                { get_role = function(self, role_id) return { id = role_id, name = "Role" } end },
                "<@&123456>"
            )
            assert.equals("123456", result.id)
            assert.equals("Role", result.name)
        end)

        it("converts role ID", function()
            local converter = M.RoleConverter

            local result = converter.convert(
                { get_role = function(self, role_id) return { id = role_id, name = "Role" } end },
                "123456"
            )
            assert.equals("123456", result.id)
            assert.equals("Role", result.name)
        end)
    end)

    describe("ChannelConverter", function()
        it("converts channel mention", function()
            local converter = M.ChannelConverter

            local result = converter.convert(
                { get_channel = function(self, channel_id) return { id = channel_id, name = "Channel" } end },
                "#123456"
            )
            assert.equals("123456", result.id)
            assert.equals("Channel", result.name)
        end)

        it("converts channel ID", function()
            local converter = M.ChannelConverter

            local result = converter.convert(
                { get_channel = function(self, channel_id) return { id = channel_id, name = "Channel" } end },
                "123456"
            )
            assert.equals("123456", result.id)
            assert.equals("Channel", result.name)
        end)
    end)
end)
