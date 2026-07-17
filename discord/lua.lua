-- discord/lua.lua
-- Package entrypoint for discord.lua, resolved by require("discord.lua").
--
-- Public Contract:
--   Bot(token) -> Bot
--     Calling the module directly constructs a Bot instance, matching the
--     README/examples convention: local client = Bot("YOUR_TOKEN")
--
--   discord.Bot -> Bot class
--     The underlying Bot class, for cases that need Bot.new(token) directly.

package.path = package.path .. ";lib/?.lua;lib/?/?.lua"

local Bot = require("commands.bot")

local M = {
    Bot = Bot,
}

setmetatable(M, {
    __call = function(_, token, ratelimiter)
        return Bot.new(token, ratelimiter)
    end,
})

return M
