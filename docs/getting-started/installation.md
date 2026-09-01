# Installation

`discord.lua` targets [Luvit](https://luvit.io/) and Lit. Install the package in your bot project:

```sh
lit install filispeen/discord.lua
```

Then load it by package name:

```lua
local discord = require("discord.lua")
```

The library creates WebSocket and HTTP clients through Luvit dependencies. Voice playback additionally uses FFmpeg, Opus, and libsodium; see [Voice limitations](../guides/voice.md#limitations-and-native-dependencies).

## Repository checkout

When running directly from a checkout, use Luvit's module path so that `require("discord.lua")` resolves to this package. The repository's `init.lua` is its package entry point.

Do not depend on `pycord/` in this repository. It is a reference copy, not part of the Lua runtime package.
