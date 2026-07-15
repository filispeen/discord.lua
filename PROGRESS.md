# M0 Progress - Bootstrap discord.lua Repository

## Completed in M0

### 1. Directory Structure
All directories from CLAUDE.md have been created:
- `lib/core/` - Core modules (class, emitter, errors)
- `lib/http/` - HTTP client and ratelimiter
- `lib/gateway/` - Gateway shard and manager
- `lib/models/` - Discord API models
- `lib/cache/` - Caching store and policy
- `lib/commands/` - ext.commands implementation
- `lib/interactions/` - Application commands
- `lib/ui/` - UI Components (View, Button, Select, Modal)
- `lib/voice/` - Voice gateway and client
- `spec/` - Busted tests
- `examples/` - Example code

### 2. lib/core/class.lua
Implemented a minimal single-inheritance class system:
- `class(name, parent)` - Create a new class with optional inheritance
- `M.__call(name, parent)` - Make module callable to create classes
- `isInstanceOf(instance, Class)` - Check if instance belongs to class or subclass
- `getName(Class)` - Get class name
- Classes are callable to create instances via metatable `__call`

### 3. lib/core/emitter.lua
Implemented event emitter pattern:
- `:on(event, fn)` - Subscribe to an event
- `:once(event, fn)` - Subscribe once then auto-unsubscribe
- `:emit(event, ...)` - Emit event with arguments
- `:off(event, fn)` - Unsubscribe from event
- `:getListeners(event)` - Get all listeners for debugging
- Method chaining via `return self`

### 4. lib/core/errors.lua
Implemented typed error classes using the class system:
- `DiscordException` - Base exception class
- `HTTPException` - HTTP errors with status_code and data
- `RateLimited` - Rate limit errors with retry_after
- `GatewayError` - WebSocket gateway errors with code
- `NotFound` - Resource not found errors with id
- `Forbidden` - Permission denied errors
- Factory functions for convenience (`.create()`)

### 5. discord-lua-scm-0.rockspec
Rockspec with dependencies:
- luvit >= 2.16.0-0
- coro-http >= 2020.0.2-0
- coro-websocket >= 2021.0.1-0
- secure-socket >= 2020.0.2-0
- Test configuration with busted

### 6. CI Configuration
- `.luacheckrc` - luacheck config with `--no-unused-args`
- `.github/workflows/ci.yml` - GitHub Actions for:
  - Linting with luacheck
  - Running busted tests
  - Validating rockspec

### 7. spec/ Tests
- `spec/class_test.lua` - 12 tests for class system
- `spec/emitter_test.lua` - 8 tests for event emitter
- `spec/main.lua` - Test runner

## Verification
```bash
luacheck --no-unused-args .
busted -p "_test.lua" spec
```

Both should pass with no errors or warnings.

## Next Milestone
**M1: HTTP + REST Core**
Start implementing `lib/http/client.lua` and `lib/http/ratelimiter.lua` for REST API communication.
