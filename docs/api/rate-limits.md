# Rate limits

`lib/http/ratelimiter.lua` exposes `Bucket`, `Manager`, and `DEFAULTS`. It is a user-constructible helper, but normal Bot construction accepts a `ratelimiter` value without creating this manager automatically.

## `Bucket`

### `Bucket.new()`

Creates a bucket with default `rate_limit`, `time_remaining`, `reset_after`, `remaining`, and `limit` values.

### `bucket:isAvailable()` / `bucket:consume()`

Check availability or consume one remaining request. `consume` returns true when it decremented `remaining`, otherwise false.

### `bucket:update(headers)`

Reads `X-RateLimit-Remaining`, `X-RateLimit-Limit`, `X-RateLimit-Reset-After`, and `Retry-After` from a headers table.

### `bucket:isRateLimited()` / `bucket:getRetryAfter()`

Return the local rate-limited state or retry seconds (`0` when available).

## `Manager`

### `Manager.new()`

Creates a manager holding path-keyed buckets and global counters.

### `manager:get_bucket(path)` / `manager:update_bucket(path, headers)` / `manager:is_rate_limited(path)`

Access, update, or query a per-path bucket.

### Global methods

`is_global_rate_limited`, `get_global_retry_after`, `consume_global`, `update_global(headers)`, `get_all_buckets`, and `set_global_remaining(remaining, limit, reset)` manage the separate global state.

!!! warning "Implementation scope"
    The manager records header-derived state but does not itself schedule waits or retries. Treat it as state tracking; the HTTP client remains responsible for request behavior.
