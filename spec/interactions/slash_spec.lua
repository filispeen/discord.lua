-- spec/interactions/slash_spec.lua
-- Tests for SlashCommandContext, focused on context menu target resolution

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local slash = require("interactions.slash")

describe("SlashCommandContext", function()
    describe("author and guild resolution", function()
        it("builds author from interaction.member.user for a guild interaction", function()
            local interaction = {
                id = "int1",
                token = "tok1",
                guild_id = "999",
                member = {
                    user = { id = "111", username = "someone" },
                },
                data = { name = "cmd", options = {} },
            }
            local ctx = slash.new(interaction, nil)
            assert.equals("111", ctx.author.id)
            assert.equals("someone", ctx.author.username)
        end)

        it("builds author from interaction.user for a DM interaction", function()
            local interaction = {
                id = "int1",
                token = "tok1",
                user = { id = "111", username = "someone" },
                data = { name = "cmd", options = {} },
            }
            local ctx = slash.new(interaction, nil)
            assert.equals("111", ctx.author.id)
        end)

        it("builds guild as a minimal id table from interaction.guild_id", function()
            local interaction = {
                id = "int1",
                token = "tok1",
                guild_id = "999",
                member = { user = { id = "111" } },
                data = { name = "cmd", options = {} },
            }
            local ctx = slash.new(interaction, nil)
            assert.equals("999", ctx.guild.id)
        end)

        it("leaves guild nil for a DM interaction with no guild_id", function()
            local interaction = {
                id = "int1",
                token = "tok1",
                user = { id = "111" },
                data = { name = "cmd", options = {} },
            }
            local ctx = slash.new(interaction, nil)
            assert.is_nil(ctx.guild)
        end)
    end)

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

        it("parses a user option via interaction.data.resolved.users, not opt.user", function()
            local interaction = {
                id = "int1",
                token = "tok1",
                data = {
                    name = "greet",
                    options = { { name = "user", type = 6, value = "555" } },
                    resolved = {
                        users = {
                            ["555"] = {
                                id = "555",
                                username = "someone",
                                discriminator = "0",
                                global_name = "Someone",
                            },
                        },
                    },
                },
            }
            local ctx = slash.new(interaction, nil)
            local user = ctx:require_arg("user")
            assert.equals("555", user.id)
            assert.equals("someone", user.username)
            assert.equals("Someone", user.global_name)
        end)

        it("falls back to a bare id table for a user option when resolved has no entry", function()
            local interaction = {
                id = "int1",
                token = "tok1",
                data = {
                    name = "greet",
                    options = { { name = "user", type = 6, value = "555" } },
                },
            }
            local ctx = slash.new(interaction, nil)
            assert.equals("555", ctx:require_arg("user").id)
        end)

        it("parses a channel option via interaction.data.resolved.channels", function()
            local interaction = {
                id = "int1",
                token = "tok1",
                data = {
                    name = "cmd",
                    options = { { name = "channel", type = 7, value = "777" } },
                    resolved = {
                        channels = {
                            ["777"] = { id = "777", type = 0, name = "general" },
                        },
                    },
                },
            }
            local ctx = slash.new(interaction, nil)
            local channel = ctx:require_arg("channel")
            assert.equals("777", channel.id)
            assert.equals("general", channel.name)
        end)

        it("parses a role option via interaction.data.resolved.roles", function()
            local interaction = {
                id = "int1",
                token = "tok1",
                data = {
                    name = "cmd",
                    options = { { name = "role", type = 8, value = "888" } },
                    resolved = {
                        roles = {
                            ["888"] = { id = "888", name = "Admins" },
                        },
                    },
                },
            }
            local ctx = slash.new(interaction, nil)
            local role = ctx:require_arg("role")
            assert.equals("888", role.id)
            assert.equals("Admins", role.name)
        end)

        it("parses a mentionable option resolving to a user", function()
            local interaction = {
                id = "int1",
                token = "tok1",
                data = {
                    name = "cmd",
                    options = { { name = "target", type = 10, value = "555" } },
                    resolved = {
                        users = { ["555"] = { id = "555", username = "someone" } },
                    },
                },
            }
            local ctx = slash.new(interaction, nil)
            local target = ctx:require_arg("target")
            assert.equals("555", target.id)
            assert.equals("user", target.type)
        end)

        it("parses a mentionable option resolving to a role", function()
            local interaction = {
                id = "int1",
                token = "tok1",
                data = {
                    name = "cmd",
                    options = { { name = "target", type = 10, value = "888" } },
                    resolved = {
                        roles = { ["888"] = { id = "888", name = "Admins" } },
                    },
                },
            }
            local ctx = slash.new(interaction, nil)
            local target = ctx:require_arg("target")
            assert.equals("888", target.id)
            assert.equals("role", target.type)
        end)

        it("parses a user option nested inside a subcommand, passing resolved down", function()
            local interaction = {
                id = "int1",
                token = "tok1",
                data = {
                    name = "group",
                    options = {
                        {
                            name = "sub",
                            type = 1,
                            options = { { name = "user", type = 6, value = "555" } },
                        },
                    },
                    resolved = {
                        users = { ["555"] = { id = "555", username = "someone" } },
                    },
                },
            }
            local ctx = slash.new(interaction, nil)
            assert.equals("555", ctx:require_arg("user").id)
        end)
    end)
end)
