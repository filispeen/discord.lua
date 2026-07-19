-- discord/lua.lua
-- Package entrypoint for discord.lua, resolved by require("discord.lua").
--
-- Public Contract:
--   Bot(ratelimiter, intents) -> Bot
--     Calling the module directly constructs a Bot instance, matching the
--     README/examples convention: local client = Bot()
--     The token is not passed here; it is passed to client:run(token).
--
--   discord.Bot -> Bot class
--     The underlying Bot class, for cases that need Bot.new(token) directly.
--
--   discord.enums -> core.enums module
--     INTENTS, combine_intents, default_intents, all_intents, OPTION_TYPE.
--     Exposed here so bots don't need a separate require("core.enums").

package.path = package.path .. ";lib/?.lua;lib/?/?.lua"

local Bot = require("commands.bot")
local enums = require("core.enums")

local M = {
    Bot = Bot,
    enums = enums,
}

setmetatable(M, {
    __call = function(_, ratelimiter, intents)
        return Bot.new(nil, ratelimiter, intents)
    end,
})

return M