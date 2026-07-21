return {
  name = "filispeen/discord.lua",
  version = "0.9.0",
  description = "Discord API wrapper written in Lua",
  tags = { "discord", "bot", "gateway", "luvit" },
  license = "MIT",
  author = { name = "filispeen" },
  homepage = "https://github.com/filispeen/discord.lua",
  dependencies = {
    "luvit/coro-http@3.2.3",
    "luvit/coro-websocket@3.1.1",
    "luvit/secure-socket@1.2.0",
    "luvit/json@2.5.2",
  },
  files = {
    "init.lua",
    "lib/**.lua",
    "README.md",
    "package.lua",
  },
}
