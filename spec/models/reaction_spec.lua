-- spec/models/reaction_spec.lua
-- Tests for reaction model

require("spec_helper")

local Reaction = require("./models/reaction")

describe("Reaction", function()
    it("creates a new reaction from a unicode emoji payload", function()
        local reaction = Reaction.new({ emoji = { name = "🔥" }, count = 3, me = true })

        assert.equals("🔥", reaction.emoji_key)
        assert.equals(3, reaction.count)
        assert.is_true(reaction.me)
        assert.is_false(reaction.me_burst)
    end)

    it("builds a name:id key for a custom emoji payload", function()
        local reaction = Reaction.new({ emoji = { id = "9", name = "pog" }, count = 1 })

        assert.equals("pog:9", reaction.emoji_key)
    end)

    it("defaults count and burst fields when missing", function()
        local reaction = Reaction.new({ emoji = { name = "🔥" } })

        assert.equals(0, reaction.count)
        assert.equals(0, reaction.count_normal)
        assert.equals(0, reaction.count_burst)
        assert.is_false(reaction.me)
        assert.is_false(reaction.me_burst)
    end)

    it("reads normal and burst counts from count_details", function()
        local reaction = Reaction.new({
            emoji = { name = "🔥" },
            count = 5,
            count_details = { normal = 3, burst = 2 },
        })

        assert.equals(3, reaction.count_normal)
        assert.equals(2, reaction.count_burst)
    end)

    it("exposes a static key helper matching instance emoji_key", function()
        assert.equals("🔥", Reaction.key({ name = "🔥" }))
        assert.equals("pog:9", Reaction.key({ id = "9", name = "pog" }))
    end)
end)
