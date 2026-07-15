# M1 Progress - HTTP and REST Core

## Completed in M1

### 1. lib/http/ratelimiter.lua
Implemented rate limit management for Discord API:
- `Bucket.new()` - Create a rate limit bucket
- `Bucket:consume()` - Attempt to consume a request
- `Bucket:update(headers)` - Update from HTTP response headers
- `Bucket:isAvailable()` - Check if request can be made
- `Manager.new()` - Create rate limit manager
- `Manager:get_bucket(path)` - Get/create bucket for API path
- `Manager:is_rate_limited(path)` - Check if path is rate limited
- `Manager:is_global_rate_limited()` - Check global rate limit
- `Manager:consume_global()` - Consume global request

### 2. lib/http/client.lua
Implemented HTTP client with rate limiting:
- `Client.new(token, ratelimiter)` - Create HTTP client
- `Client:request(method, endpoint, options)` - Generic HTTP request
- `Client:get/post/put/delete(endpoint, ...)` - HTTP method wrappers
- `Client:parse_json(response)` - Parse JSON response
- `Client:throw_error(status, data)` - Create appropriate error
- Automatic rate limit checking and retry logic

### 3. lib/models/
Created basic Discord API models:
- **user.lua** - User model (id, username, discriminator, avatar, bot flag, etc.)
- **channel.lua** - Channel model (type, name, parent_id, permissions, etc.)
- **guild.lua** - Guild model (name, icon, owner_id, roles, channels, etc.)
- **message.lua** - Message model (content, author, embeds, reactions, etc.)
- **member.lua** - Member model (user, roles, join date, mute/deaf, etc.)
- **role.lua** - Role model (name, color, hoist, permissions, etc.)
- **embed.lua** - Embed model with builder methods (`:with_author()`, `:with_field()`, etc.)
- **emoji.lua** - Emoji model
- **webhook.lua** - Webhook model with `:send()` method
- **client.lua** - Main client model with event system and API wrappers

### 4. lib/commands/
Implemented ext.commands foundation:
- **bot.lua** - Bot class with command registration
- **cog.lua** - Cog class for organizing commands
- **command.lua** - Command class with description, usage, aliases
- **group.lua** - Command group class for subcommands
- **converters.lua** - Type converters (string, integer, boolean, user, member, role, channel)
- **checks.lua** - Command checks (owner, admin, staff, mod, user, guild, bot)

### 5. lib/interactions/
Implemented application command support:
- **application_command.lua** - Application command class
- **slash.lua** - Slash command context for parsing arguments
- **context_menu.lua** - Context menu (user/message) commands
- **hybrid.lua** - Hybrid commands (prefix + slash)

### 6. Dependencies
Added `json` package to rockspec and CI

## Verification
```bash
luacheck --no-unused-args lib/  # ✓ 0 warnings, 0 errors
```

## Next Milestone
**M2: Gateway Core**
Implement gateway functionality:
- Gateway shard manager
- WebSocket connection handling
- Identify/Resume protocols
- Heartbeat mechanism
- Event dispatch system
