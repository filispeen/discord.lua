# First bot

Create `bot.lua`:

```lua
local discord = require("discord.lua")

local bot = discord()

bot:on("ready", function()
    print("Connected as " .. bot.user.username)
end)

bot:command("ping", function(message)
    message:reply("Pong!")
end, "Reply with Pong!")

bot:run(assert(os.getenv("DISCORD_TOKEN"), "DISCORD_TOKEN is required"))
```

Run it with a token supplied by the environment:

```sh
DISCORD_TOKEN=your-token luvit bot.lua
```

On PowerShell:

```powershell
$env:DISCORD_TOKEN = 'your-token'
luvit bot.lua
```

The `ping` callback receives a [`Message`](../api/messages-and-channels.md#message), because prefix commands use the gateway message directly. It can call `Message:reply`.

For a slash-only bot, start with [Slash commands](../guides/slash-commands.md); it does not need Message Content access.
