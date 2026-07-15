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

---

## M2 Progress - Gateway Core

## Completed in M2

### 1. lib/gateway/opcodes.lua
Implemented gateway opcodes:
- `CONNECT = 0` - Initial handshake
- `IDENTIFY = 2` - Bot identification  
- `READY = 10` - Ready event from Discord
- `HEARTBEAT = 1` - Heartbeat sent by bot
- `HEARTBEAT_ACK = 10` - Heartbeat acknowledgment
- `RESUME = 12` - Session resume
- `DISCONNECTED = 11` - Disconnection event
- `RECONNECT = 7` - Reconnect instruction

### 2. lib/gateway/shard.lua
Implemented single shard WebSocket connection:
- `Shard.new(client, shard_id, total_shards)` - Create shard
- `Shard:connect()` - Connect to gateway
- `Shard:identify(data)` - Send identify packet
- `Shard:resume(session_id, seq)` - Resume session
- `Shard:send_heartbeat()` - Send heartbeat with luvit Timer
- `Shard:close()` - Close WebSocket connection
- `Shard:dispatch(event)` - Dispatch event to listeners
- `Shard:emit(event, ...)` - Emit event to listeners
- `Shard:on_ready(callback)` - Listen for READY event
- `Shard:on_event(event, callback)` - Listen for gateway events
- `Shard:on_disconnect(callback)` - Listen for disconnect
- `Shard:on_error(callback)` - Listen for errors
- Internal state management (seq, heartbeat_interval, missed_acks)
- Heartbeat tracking with ACK verification (3 missed = reconnect)

### 3. lib/gateway/manager.lua
Implemented shard manager:
- `ShardManager.new(client, max_concurrency)` - Create manager
- `ShardManager:start()` - Start all shards
- `ShardManager:stop()` - Stop all shards
- `ShardManager:get_shard(id)` - Get shard by ID
- `ShardManager:shards()` - Get all shards
- `ShardManager:dispatch(event)` - Dispatch event to all shards
- `ShardManager:on_ready(callback)` - Listen for bot ready
- `ShardManager:on_shard_ready(shard_id, callback)` - Listen for shard ready
- `ShardManager:on_shard_error(shard_id, callback)` - Listen for shard error
- `ShardManager:on_shard_disconnect(shard_id, callback)` - Listen for shard disconnect
- Respects max_concurrency from /gateway/bot
- Sequential shard startup for concurrency control

### 4. lib/models/client.lua
Integrated gateway with main client:
- Added `gateway` field to Client
- Added `:start_gateway()` method
- Added `:stop_gateway()` method
- Gateway event listeners:
  - `on_gateway_ready(callback)`
  - `on_gateway_shard_ready(shard_id, callback)`
  - `on_gateway_shard_error(shard_id, callback)`
  - `on_gateway_shard_disconnect(shard_id, callback)`
  - `on_gateway_event(callback)`
- Gateway dispatch methods for events

### 5. spec/gateway/
Created comprehensive tests:
- `opcodes_spec.lua` - Verify all opcodes are defined correctly
- `shard_spec.lua` - Test shard lifecycle and state management
- `manager_spec.lua` - Test shard manager functionality
- Mock `mock_luv.lua` - Mock luvit Timer for testing

## Verification

```bash
luacheck --no-unused-args lib/gateway/ lib/models/client.lua  # 0 warnings, 0 errors
busted spec/                                                   # 8 successes / 0 failures
```

## Next Milestone
**M3: Cache and full models**
Implement caching system and complete model definitions:
- Cache store (LRU)
- Cache policy (TTL, max entries)
- Complete model fields (Role, Emoji, Sticker, Invite, Webhook, Embed)
- Permission bitmath
