# Embeds and files

Create embeds with `bot:embed(data)` or the underlying `Embed.new(data)` API.

```lua
local embed = bot:embed({ title = "Build" })
    :description("Succeeded")
    :with_color(discord.Colour.green())
    :with_field("Duration", "12 seconds", true)

bot:command("build", function(message)
    message:reply("", { embeds = { embed } })
end)
```

Embeds are Lua tables when they reach the HTTP layer. Use a list even for one embed: `embeds = { embed }`.

## Files

Message replies, edits, and interaction responses accept `opts.files` as an array. The library builds multipart payloads when the array is present. Use the model file constructor; `discord.ui.File` is a Components v2 display item, not an upload.

```lua
local File = require("discord.lua/lib/models/file")

ctx:respond("Attached", {
    files = {
        File.from_bytes("contents", "report.txt", {
            content_type = "text/plain",
        }),
    },
})
```

Use `AllowedMentions` when a message payload needs explicit mention parsing controls. See the [model reference](../api/embeds-assets-and-mentions.md).
