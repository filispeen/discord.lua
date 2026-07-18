-- lib/core/enums.lua
-- Core enum constants shared across the library, gateway intents in
-- particular. Bit positions mirror Discord's Gateway Intents documentation
-- and pycord's discord.Intents.
--
-- Public Contract:
--   INTENTS: table of name -> bit value
--     Individual intent flags, e.g. INTENTS.GUILDS, INTENTS.GUILD_MESSAGES.
--
--   combine_intents(...) -> number
--     Bitwise ORs any number of intent values together.
--
--   default_intents() -> number
--     Intents with no privileged intents enabled: guilds, guild messages,
--     dm messages, reactions, typing, invites, webhooks, integrations,
--     voice states, emojis and stickers, scheduled events, polls.
--     Excludes members, presences, message_content (all privileged).
--
--   all_intents() -> number
--     Every intent bit including privileged ones.

-- luvit/LuaJIT expose a global `bit` module (bit.bor); plain Lua 5.1 does
-- not, so bor() below falls back to pure arithmetic in that case.
local has_bit_lib = rawget(_G, "bit") ~= nil

local M = {}

M.INTENTS = {
    GUILDS = 1,
    GUILD_MEMBERS = 2,
    GUILD_MODERATION = 4,
    GUILD_EMOJIS_AND_STICKERS = 8,
    GUILD_INTEGRATIONS = 16,
    GUILD_WEBHOOKS = 32,
    GUILD_INVITES = 64,
    GUILD_VOICE_STATES = 128,
    GUILD_PRESENCES = 256,
    GUILD_MESSAGES = 512,
    GUILD_MESSAGE_REACTIONS = 1024,
    GUILD_MESSAGE_TYPING = 2048,
    DIRECT_MESSAGES = 4096,
    DIRECT_MESSAGE_REACTIONS = 8192,
    DIRECT_MESSAGE_TYPING = 16384,
    MESSAGE_CONTENT = 32768,
    GUILD_SCHEDULED_EVENTS = 65536,
    AUTO_MODERATION_CONFIGURATION = 1048576,
    AUTO_MODERATION_EXECUTION = 2097152,
    GUILD_MESSAGE_POLLS = 16777216,
    DIRECT_MESSAGE_POLLS = 33554432,
}

-- Intents that Discord requires opting in to on the developer portal.
M.PRIVILEGED_INTENTS = {
    M.INTENTS.GUILD_MEMBERS,
    M.INTENTS.GUILD_PRESENCES,
    M.INTENTS.MESSAGE_CONTENT,
}

local function bor(a, b)
    if has_bit_lib then
        return _G.bit.bor(a, b)
    end
    -- Fallback bitwise or for environments without bit32/bit (Lua 5.1 without
    -- luvit's bit library loaded). Values here fit well within 32 bits.
    local result = 0
    local bitval = 1
    while a > 0 or b > 0 do
        local abit = a % 2
        local bbit = b % 2
        if abit == 1 or bbit == 1 then
            result = result + bitval
        end
        a = (a - abit) / 2
        b = (b - bbit) / 2
        bitval = bitval * 2
    end
    return result
end

function M.combine_intents(...)
    local result = 0
    for _, value in ipairs({ ... }) do
        result = bor(result, value)
    end
    return result
end

function M.default_intents()
    local privileged = {}
    for _, value in ipairs(M.PRIVILEGED_INTENTS) do
        privileged[value] = true
    end

    local values = {}
    for _, value in pairs(M.INTENTS) do
        if not privileged[value] then
            table.insert(values, value)
        end
    end

    return M.combine_intents(unpack(values))
end

function M.all_intents()
    local values = {}
    for _, value in pairs(M.INTENTS) do
        table.insert(values, value)
    end
    return M.combine_intents(unpack(values))
end

-- Application command option types, per Discord's Application Command
-- Option Type documentation. Used when building slash command options
-- instead of writing the raw numbers inline.
M.OPTION_TYPE = {
    SUB_COMMAND = 1,
    SUB_COMMAND_GROUP = 2,
    STRING = 3,
    INTEGER = 4,
    BOOLEAN = 5,
    USER = 6,
    CHANNEL = 7,
    ROLE = 8,
    MENTIONABLE = 10,
    NUMBER = 11,
    ATTACHMENT = 12,
}

return M
