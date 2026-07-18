-- spec/core/enums_spec.lua
-- Tests for gateway intent enums

package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

local enums = require("core.enums")

local function has_bit(value, bit_flag)
    return math.floor(value / bit_flag) % 2 == 1
end

describe("enums", function()
    it("defines the GUILDS intent as bit 0", function()
        assert.equals(1, enums.INTENTS.GUILDS)
    end)

    it("defines GUILD_MESSAGES as bit 9", function()
        assert.equals(512, enums.INTENTS.GUILD_MESSAGES)
    end)

    it("defines MESSAGE_CONTENT as bit 15", function()
        assert.equals(32768, enums.INTENTS.MESSAGE_CONTENT)
    end)

    it("combines intents with bitwise or", function()
        local combined = enums.combine_intents(enums.INTENTS.GUILDS, enums.INTENTS.GUILD_MESSAGES)
        assert.equals(513, combined)
    end)

    it("combining the same intent twice does not double count it", function()
        local combined = enums.combine_intents(enums.INTENTS.GUILDS, enums.INTENTS.GUILDS)
        assert.equals(1, combined)
    end)

    it("default_intents excludes privileged intents", function()
        local default = enums.default_intents()

        assert.is_false(has_bit(default, enums.INTENTS.GUILD_MEMBERS))
        assert.is_false(has_bit(default, enums.INTENTS.GUILD_PRESENCES))
        assert.is_false(has_bit(default, enums.INTENTS.MESSAGE_CONTENT))
    end)

    it("default_intents includes GUILDS and GUILD_MESSAGES", function()
        local default = enums.default_intents()

        assert.is_true(has_bit(default, enums.INTENTS.GUILDS))
        assert.is_true(has_bit(default, enums.INTENTS.GUILD_MESSAGES))
    end)

    it("all_intents includes every intent bit including privileged ones", function()
        local all = enums.all_intents()

        assert.is_true(has_bit(all, enums.INTENTS.GUILD_MEMBERS))
        assert.is_true(has_bit(all, enums.INTENTS.MESSAGE_CONTENT))
    end)

    it("defines application command option types matching Discord's schema", function()
        assert.equals(3, enums.OPTION_TYPE.STRING)
        assert.equals(6, enums.OPTION_TYPE.USER)
        assert.equals(7, enums.OPTION_TYPE.CHANNEL)
    end)
end)
