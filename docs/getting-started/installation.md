# Installation

`discord.lua` targets [Luvit](https://luvit.io/) and Lit. Install the package in your bot project:

```sh
lit install filispeen/discord.lua
```

Then load it by package name:

```lua
local discord = require("discord.lua")
```

The library creates WebSocket and HTTP clients through Luvit dependencies. Voice playback additionally uses FFmpeg, Opus, libsodium, and libdave; see [Voice limitations](../guides/voice.md#limitations-and-native-dependencies).

## Native voice bundle

The package does not include native binaries in the Lit download. On Linux x64 and Windows x64, the first `require("discord.lua")` automatically downloads the release asset matching the package version into `lib/bundle/`, providing FFmpeg, FFprobe, Opus, libsodium, and libdave.

On Linux this requires `curl` and `tar`; on Windows it uses PowerShell's `Invoke-WebRequest` and `Expand-Archive`.

Only Linux x64 and Windows x64 have automatic bundles. On other platforms, install compatible FFmpeg, Opus, libsodium, and libdave libraries through the system and make them available to the runtime.

## Repository checkout

When running directly from a checkout, use Luvit's module path so that `require("discord.lua")` resolves to this package. The repository's `init.lua` is its package entry point.

Do not depend on `pycord/` in this repository. It is a reference copy, not part of the Lua runtime package.
