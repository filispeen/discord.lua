-- spec/commands/converters_spec.lua
-- Tests for converters

-- Setup package path to find lib modules
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
            local mock_ctx = {
                client = {
                    get_user = function(id)
                        return { id = id, username = "Test" }
                    end
                }
            }

            assert.equals("123456", converter.convert(mock_ctx, "<@123456>"))
        end)

        it("converts user ID", function()
            local converter = M.UserConverter
            local mock_ctx = {
                client = {
                    get_user = function(id)
                        return { id = id, username = "Test" }
                    end
                }
            }

            assert.equals("123456", converter.convert(mock_ctx, "123456"))
        end)
    end)

    describe("MemberConverter", function()
        it("converts member mention", function()
            local converter = M.MemberConverter
            local mock_ctx = {
                client = {
                    get_member = function(guild_id, user_id)
                        return { user = { id = user_id }, roles = { guild_id } }
                    end
                }
            }

            assert.equals("123456", converter.convert(mock_ctx, "<@&123456>"))
        end)

        it("converts member ID", function()
            local converter = M.MemberConverter
            local mock_ctx = {
                client = {
                    get_member = function(guild_id, user_id)
                        return { user = { id = user_id }, roles = { guild_id } }
                    end
                }
            }

            assert.equals("123456", converter.convert(mock_ctx, "123456"))
        end)
    end)

    describe("RoleConverter", function()
        it("converts role mention", function()
            local converter = M.RoleConverter
            local mock_ctx = {
                guild = {
                    get_role = function(id)
                        return { id = id, name = "Role" }
                    end
                }
            }

            assert.equals("123456", converter.convert(mock_ctx, "<@&123456>"))
        end)

        it("converts role ID", function()
            local converter = M.RoleConverter
            local mock_ctx = {
                guild = {
                    get_role = function(id)
                        return { id = id, name = "Role" }
                    end
                }
            }

            assert.equals("123456", converter.convert(mock_ctx, "123456"))
        end)
    end)

    describe("ChannelConverter", function()
        it("converts channel mention", function()
            local converter = M.ChannelConverter
            local mock_ctx = {
                guild = {
                    get_channel = function(id)
                        return { id = id, name = "Channel" }
                    end
                }
            }

            assert.equals("123456", converter.convert(mock_ctx, "<#123456>"))
        end)

        it("converts channel ID", function()
            local converter = M.ChannelConverter
            local mock_ctx = {
                guild = {
                    get_channel = function(id)
                        return { id = id, name = "Channel" }
                    end
                }
            }

            assert.equals("123456", converter.convert(mock_ctx, "123456"))
        end)
    end)
end)
