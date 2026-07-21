-- spec/interactions/slash_spec.lua
-- Tests for SlashCommandContext, focused on context menu target resolution

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local slash = require("interactions.slash")

describe("SlashCommandContext", function()
    describe("target resolution for context menu commands", function()
        it("resolves target_user from resolved.members when present", function()
            local interaction = {
                id = "int1",
                token = "tok1",
                data = {
                    name = "mention",
                    target_id = "42",
                    resolved = {
                        members = { ["42"] = { id = "42", nick = "Someone" } },
                    },
                },
            }
            local ctx = slash.new(interaction, nil)
            assert.equals("42", ctx.target_user.id)
        end)

        it("falls back to resolved.users when no member entry exists", function()
            local interaction = {
                id = "int1",
                token = "tok1",
                data = {
                    name = "mention",
                    target_id = "42",
                    resolved = {
                        users = { ["42"] = { id = "42", username = "someone" } },
                    },
                },
            }
            local ctx = slash.new(interaction, nil)
            assert.equals("42", ctx.target_user.id)
        end)

        it("resolves target_message from resolved.messages", function()
            local interaction = {
                id = "int1",
                token = "tok1",
                data = {
                    name = "Show ID",
                    target_id = "99",
                    resolved = {
                        messages = { ["99"] = { id = "99", content = "hi" } },
                    },
                },
            }
            local ctx = slash.new(interaction, nil)
            assert.equals("99", ctx.target_message.id)
        end)

        it("leaves target_user and target_message nil for a regular slash command", function()
            local interaction = {
                id = "int1",
                token = "tok1",
                data = { name = "ping", options = {} },
            }
            local ctx = slash.new(interaction, nil)
            assert.is_nil(ctx.target_user)
            assert.is_nil(ctx.target_message)
        end)
    end)

    describe("SlashCommandContext:get_arg and :require_arg", function()
        it("get_arg returns the default when the argument is missing", function()
            local interaction = { id = "int1", token = "tok1", data = { name = "cmd", options = {} } }
            local ctx = slash.new(interaction, nil)
            assert.equals("fallback", ctx:get_arg("missing", "fallback"))
        end)

        it("require_arg errors when the argument is missing", function()
            local interaction = { id = "int1", token = "tok1", data = { name = "cmd", options = {} } }
            local ctx = slash.new(interaction, nil)
            assert.has_error(function()
                ctx:require_arg("missing")
            end)
        end)

        it("parses a string option into args", function()
            local interaction = {
                id = "int1",
                token = "tok1",
                data = { name = "cmd", options = { { name = "query", type = 3, value = "hello" } } },
            }
            local ctx = slash.new(interaction, nil)
            assert.equals("hello", ctx:require_arg("query"))
        end)
    end)
end)
