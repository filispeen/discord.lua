-- spec/ext/bridge/bridge_context_spec.lua
-- Tests for BridgeContext

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local BridgeContext = require("ext.bridge.bridge_context")

local function make_message()
    local calls = {}
    return {
        author = { id = "user1" },
        guild = { id = "guild1" },
        channel = { id = "channel1" },
        bot = { id = "bot1" },
        reply = function(_self, content)
            table.insert(calls, content)
            return { ok = true }
        end,
    }, calls
end

local function make_slash_ctx()
    local respond_calls, edit_calls = {}, {}
    return {
        author = { id = "user1" },
        guild = { id = "guild1" },
        channel = { id = "channel1" },
        bot = { id = "bot1", rest = { post = function() end } },
        args = { foo = "bar" },
        interaction_id = "int1",
        interaction_token = "token1",
        respond = function(_self, content, opts)
            table.insert(respond_calls, { content = content, opts = opts })
            return { ok = true }
        end,
        edit = function(_self, content, opts)
            table.insert(edit_calls, { content = content, opts = opts })
            return { ok = true }
        end,
    }, respond_calls, edit_calls
end

describe("BridgeContext", function()
    describe("prefix source", function()
        it("sets is_app to false", function()
            local message = make_message()
            local ctx = BridgeContext.new(message, "prefix")
            assert.is_false(ctx.is_app)
        end)

        it("exposes author, guild, channel, bot from the message", function()
            local message = make_message()
            local ctx = BridgeContext.new(message, "prefix")
            assert.equals(message.author, ctx.author)
            assert.equals(message.guild, ctx.guild)
            assert.equals(message.channel, ctx.channel)
            assert.equals(message.bot, ctx.bot)
        end)

        it("respond calls Message:reply", function()
            local message, calls = make_message()
            local ctx = BridgeContext.new(message, "prefix")
            ctx:respond("hello")
            assert.equals(1, #calls)
            assert.equals("hello", calls[1])
        end)

        it("defer is a no-op on the prefix path", function()
            local message = make_message()
            local ctx = BridgeContext.new(message, "prefix")
            assert.is_nil(ctx:defer())
        end)

        it("followup:send falls back to Message:reply", function()
            local message, calls = make_message()
            local ctx = BridgeContext.new(message, "prefix")
            ctx.followup:send("psst")
            assert.equals(1, #calls)
            assert.equals("psst", calls[1])
        end)
    end)

    describe("app source", function()
        it("sets is_app to true", function()
            local slash_ctx = make_slash_ctx()
            local ctx = BridgeContext.new(slash_ctx, "app")
            assert.is_true(ctx.is_app)
        end)

        it("first respond call sends an interaction response", function()
            local slash_ctx, respond_calls = make_slash_ctx()
            local ctx = BridgeContext.new(slash_ctx, "app")
            ctx:respond("hi")
            assert.equals(1, #respond_calls)
            assert.equals("hi", respond_calls[1].content)
        end)

        it("second respond call edits the existing response instead", function()
            local slash_ctx, respond_calls, edit_calls = make_slash_ctx()
            local ctx = BridgeContext.new(slash_ctx, "app")
            ctx:respond("hi")
            ctx:respond("hi again")
            assert.equals(1, #respond_calls)
            assert.equals(1, #edit_calls)
            assert.equals("hi again", edit_calls[1].content)
        end)

        it("exposes args from the SlashCommandContext", function()
            local slash_ctx = make_slash_ctx()
            local ctx = BridgeContext.new(slash_ctx, "app")
            assert.equals("bar", ctx.args.foo)
        end)
    end)
end)
