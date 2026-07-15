package = {
    name =    "discord-lua",
    version = "0.1.0",
    description = "A port of pycord to Lua on top of Luvit",
    license = "MIT",
    author = "discord.lua developers",
    url = "https://github.com/discord-lua/discord.lua",
}

source = {
    files = {
        "lib/",
        "spec/",
        "examples/",
    },
}

build = {
    type = "builtin",
}

dependencies = {
    "luvit >= 2.16.0-0",
    "coro-http >= 2020.0.2-0",
    "coro-websocket >= 2021.0.1-0",
    "secure-socket >= 2020.0.2-0",
}

local_lua = true

test = {
    pattern = "spec/*_test.lua",
    main = "spec.main",
}
