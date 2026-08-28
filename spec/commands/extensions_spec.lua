require("spec_helper")

local Bot = require("./commands/bot")

describe("Bot extensions", function()
    after_each(function()
        package.preload["test_extension"] = nil
        package.preload["failing_extension"] = nil
        package.loaded["test_extension"] = nil
        package.loaded["failing_extension"] = nil
    end)

    it("loads, unloads, and reloads setup registrations", function()
        local setups, teardowns = 0, 0
        package.preload["test_extension"] = function()
            return {
                setup = function(bot)
                    setups = setups + 1
                    bot:command("extension", function() return setups end)
                    return function()
                        teardowns = teardowns + 1
                    end
                end,
            }
        end
        local bot = Bot.new("token")
        bot:command("original", function() end)

        local extension = bot:load_extension("test_extension")

        assert.is_not_nil(extension)
        assert.equals(1, bot.commands.extension())
        assert.is_true(bot.extensions.test_extension ~= nil)

        assert.is_true(bot:unload_extension("test_extension"))
        assert.is_nil(bot.commands.extension)
        assert.is_not_nil(bot.commands.original)
        assert.equals(1, teardowns)

        bot:load_extension("test_extension")
        assert.equals(2, bot.commands.extension())
        assert.equals(2, setups)
    end)

    it("restores state when setup fails", function()
        package.preload["failing_extension"] = function()
            return {
                setup = function(bot)
                    bot:command("partial", function() end)
                    error("setup failure")
                end,
            }
        end
        local bot = Bot.new("token")

        assert.has_error(function()
            bot:load_extension("failing_extension")
        end)
        assert.is_nil(bot.commands.partial)
        assert.is_nil(bot.extensions.failing_extension)
    end)
end)
