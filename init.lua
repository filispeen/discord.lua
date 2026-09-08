-- discord/lua.lua
-- Package entrypoint for discord.lua, resolved by require("./discord/lua").
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
--     Exposed here so bots don't need a separate require("./core/enums").

local function bundle_missing()
    local ffi_ok, ffi = pcall(require, "ffi")
    if not ffi_ok or ffi.arch ~= "x64" then return false end

    local source = debug.getinfo(1, "S").source
    local root = source:match("^@(.+)[/\\][^/\\]+$")
    if not root then return false end

    local required = ffi.os == "Linux" and {
        "linux-x64/bin/ffmpeg", "linux-x64/bin/ffprobe", "linux-x64/lib/libsodium.so",
        "linux-x64/lib/libopus.so", "linux-x64/lib/libdave.so",
    } or ffi.os == "Windows" and {
        "windows-x64/bin/ffmpeg.exe", "windows-x64/bin/ffprobe.exe", "windows-x64/dll/libopus-0.x64.dll",
        "windows-x64/dll/libsodium-x64.dll", "windows-x64/dll/libdave-x64.dll", "windows-x64/dll/libssp-0.dll",
    }
    if not required then return false end

    for _, path in ipairs(required) do
        local file = io.open(root .. "/lib/bundle/" .. path, "rb")
        if not file then return true end
        file:close()
    end
    return false
end

if bundle_missing() then
    local installed, err = pcall(require, "./install")
    if not installed then io.stderr:write("discord.lua: native bundle unavailable: " .. err .. "\n") end
end

-- coro-net requires "coro-channel" internally cause go daym it work so bad. Keep the implementation
-- inside this package so installed copies do not depend on a bundled deps/
-- directory.
local utils = require("./lib/utils")
package.preload["coro-channel"] = function()
    return utils
end
package.loaded["coro-channel"] = utils

local Bot = require("./lib/commands/bot")
local enums = require("./lib/core/enums")

local M = {
    Bot = Bot,
    enums = enums,
    Asset = require("./lib/models/asset"),
    Colour = require("./lib/models/colour").Colour,
    Color = require("./lib/models/colour").Color,
    PartialEmoji = require("./lib/models/partial_emoji"),
    AllowedMentions = require("./lib/models/allowed_mentions"),
    Flags = require("./lib/models/flags"),
    Permissions = require("./lib/models/permission").Permissions,
    ui = {
        ActionRow = require("./lib/ui/action_row"),
        Checkbox = require("./lib/ui/checkbox"),
        CheckboxGroup = require("./lib/ui/checkbox_group"),
        RadioGroup = require("./lib/ui/radio_group"),
        InputText = require("./lib/ui/input_text"),
        File = require("./lib/ui/file"),
    },
}

setmetatable(M, {
    __call = function(_, ratelimiter, intents)
        return Bot.new(nil, ratelimiter, intents)
    end,
})

return M
