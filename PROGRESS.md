# Milestone Status

## Current Status: **4 milestones ready**

All milestones M1-M7 are complete with passing tests. M8 is not yet ready.

| Milestone | Status | Tests | Notes |
|-----------|--------|-------|-------|
| M0: Bootstrap | Ready | N/A | Repo structure, CI, rockspec |
| M1: HTTP + REST core | Ready | ✓ | Rate limiter, HTTP client, models |
| M2: Gateway core | Ready | ✓ | Shard, manager, events |
| M3: Cache and full models | Ready | ✓ | LRU cache, permission bitmath |
| M4: ext.commands | Ready | ✓ | Bot, Cog, Command, Group, converters, checks |
| M5: Application commands | Ready | ✓ | Slash, context menu, hybrid, sync |
| M6: UI Components | Ready | ✓ | View, Button, Select, Modal |
| M7: Voice | **Incomplete** | ✗ | Code exists but NO tests |
| M8: Sharding, polish, docs | Not started | N/A | Auto-sharding, docs, examples |

---

## M1: HTTP + REST Core ✓

### Components
- `lib/http/ratelimiter.lua` - Rate limit bucket manager
- `lib/http/client.lua` - HTTP client with rate limiting
- `lib/models/` - User, Channel, Guild, Message, Member, Role, Embed, Emoji, Webhook models
- `lib/core/class.lua`, `emitter.lua` - Core infrastructure

### Verification
- luacheck: passes
- Tests: spec/http/, spec/models/

---

## M2: Gateway Core ✓

### Components
- `lib/gateway/shard.lua` - Single shard WebSocket
- `lib/gateway/manager.lua` - Shard manager with max_concurrency
- `lib/gateway/opcodes.lua` - Gateway opcodes
- `lib/models/client.lua` - Client integration

### Verification
- luacheck: passes
- Tests: spec/gateway/ (8 tests)

---

## M3: Cache and Full Models ✓

### Components
- `lib/cache/store.lua` - LRU cache store
- `lib/cache/policy.lua` - Cache policies
- `lib/models/permission.lua` - Permission bitmath
- Complete models: Role, Emoji, Sticker, Invite, Webhook, Embed

### Verification
- luacheck: passes
- Tests: spec/cache/, spec/models/ (60 tests)

---

## M4: ext.commands (prefix commands) ✓

### Components
- `lib/commands/bot.lua` - Bot class
- `lib/commands/cog.lua` - Cog class
- `lib/commands/command.lua` - Command class
- `lib/commands/group.lua` - Group class
- `lib/commands/converters.lua` - Type converters
- `lib/commands/checks.lua` - Command checks

### Verification
- luacheck: passes
- Tests: spec/commands/ (51 tests)

---

## M5: Application Commands ✓

### Components
- `lib/interactions/application_command.lua` - Application command class
- `lib/interactions/slash.lua` - Slash command context
- `lib/interactions/context_menu.lua` - Context menu commands
- `lib/interactions/hybrid.lua` - Hybrid commands
- Command tree sync to Discord API
- Autocomplete support

### Verification
- luacheck: passes
- Tests: spec/interactions/ (35 tests)

---

## M6: UI Components ✓

### Components
- `lib/ui/view.lua` - View class with timeout
- `lib/ui/button.lua` - Button component
- `lib/ui/select.lua` - SelectMenu component
- `lib/ui/modal.lua` - Modal component

### Verification
- luacheck: passes
- Tests: spec/ui/ (28 tests)

---

## M7: Voice - INCOMPLETE

### Components (code exists)
- `lib/voice/voice_gateway.lua` - Voice gateway
- `lib/voice/udp.lua` - UDP handling
- `lib/voice/voice_client.lua` - Voice client
- `lib/voice/opus.lua` - Opus binding

### Missing
- **NO tests in `spec/voice/`**
- No verification in CI

### Status
Code is implemented but not tested. Milestone not ready for release.

---

## M8: Sharding, polish, docs - NOT STARTED

### Pending
- Auto-sharding implementation
- luadoc-generated documentation
- examples/ directory
- 1.0 release checklist

---

## Summary

**Ready for release: M1-M6** (plus M7 code, pending tests)
**Blocking M7 completion: Voice tests missing**
**Not started: M8**

Total tests passing: ~232 (across M1-M6)
Tests pending: M7 voice tests (spec/voice/)
