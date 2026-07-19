package = {
    name =    "discord-lua",
    version = "0.8.0",
    description = "Discord API wrapper written in Lua",
    license = "MIT",
    author = "filispeen",
    url = "https://github.com/filispeen/discord.lua",
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
    "json >= 2021.0.1-0",
}

test = {
    pattern = "spec/*_test.lua",
    main = "spec.main",
}
