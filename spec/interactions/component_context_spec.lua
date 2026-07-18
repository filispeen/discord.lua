-- spec/interactions/component_context_spec.lua
-- Tests for ComponentContext, the response helper for button/select
-- (MESSAGE_COMPONENT) interactions.

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local ComponentContext = require("interactions.component_context")

local function make_client(calls)
    return {
        rest = {
            create_interaction_response = function(_self, interaction_id, interaction_token, payload)
                table.insert(calls, {
                    interaction_id = interaction_id,
                    interaction_token = interaction_token,
                    payload = payload,
                })
            end,
        },
    }
end

describe("ComponentContext", function()
    it("copies fields from the raw interaction onto itself", function()
        local ctx = ComponentContext.new({ id = "1", token = "tok", custom_id = "vote_up" }, nil)

        assert.equals("vote_up", ctx.custom_id)
        assert.equals("1", ctx.interaction_id)
        assert.equals("tok", ctx.interaction_token)
    end)

    it("respond sends a type 4 CHANNEL_MESSAGE_WITH_SOURCE response", function()
        local calls = {}
        local client = make_client(calls)
        local ctx = ComponentContext.new({ id = "1", token = "tok", custom_id = "vote_up" }, client)

        ctx:respond("Thanks for voting!")

        assert.equals(1, #calls)
        assert.equals(4, calls[1].payload.type)
        assert.equals("Thanks for voting!", calls[1].payload.data.content)
    end)

    it("update sends a type 7 UPDATE_MESSAGE response", function()
        local calls = {}
        local client = make_client(calls)
        local ctx = ComponentContext.new({ id = "1", token = "tok", custom_id = "vote_up" }, client)

        ctx:update("Votes: 5")

        assert.equals(7, calls[1].payload.type)
        assert.equals("Votes: 5", calls[1].payload.data.content)
    end)

    it("respond sets the ephemeral flag when requested", function()
        local calls = {}
        local client = make_client(calls)
        local ctx = ComponentContext.new({ id = "1", token = "tok" }, client)

        ctx:respond("Only you can see this", { ephemeral = true })

        assert.equals(64, calls[1].payload.data.flags)
    end)

    it("defer sends type 6 DEFERRED_UPDATE_MESSAGE by default", function()
        local calls = {}
        local client = make_client(calls)
        local ctx = ComponentContext.new({ id = "1", token = "tok" }, client)

        ctx:defer()

        assert.equals(6, calls[1].payload.type)
    end)

    it("defer sends type 5 when with_message is set", function()
        local calls = {}
        local client = make_client(calls)
        local ctx = ComponentContext.new({ id = "1", token = "tok" }, client)

        ctx:defer({ with_message = true })

        assert.equals(5, calls[1].payload.type)
    end)

    it("errors when responding without a rest client attached", function()
        local ctx = ComponentContext.new({ id = "1", token = "tok" }, nil)

        assert.has_error(function()
            ctx:respond("hi")
        end)
    end)
end)
