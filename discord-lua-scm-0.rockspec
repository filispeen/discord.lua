rockspec_format = "3.0"

package = "discord-lua"
version = "scm-0"

source = {
    url = "git+https://github.com/filispeen/discord.lua.git",
}

description = {
    summary = "Discord API wrapper written in Lua",
    homepage = "https://github.com/filispeen/discord.lua",
    license = "MIT",
    maintainer = "filispeen",
}

dependencies = {
    "lua >= 5.1",
    "luvit >= 2.16.0-0",
    "coro-http >= 2020.0.2-0",
    "coro-websocket >= 2021.0.1-0",
    "secure-socket >= 2020.0.2-0",
    "json >= 2021.0.1-0",
}

build = {
    type = "builtin",
}
