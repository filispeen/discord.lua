-- lib/http/client.lua
-- HTTP client for Discord REST API with rate limiting
--
-- Public Contract:
--   Client.new(token, ratelimiter) -> client_table
--     Creates a new HTTP client.
--     token: string - Discord bot token
--     ratelimiter: table - rate limiter manager (from ratelimiter.lua)
--     Returns: client_table with :request, :get, :post, :put, :delete methods
--
--   Client:request(method, endpoint, options) -> response
--     Makes an HTTP request to Discord API.
--     method: "GET" | "POST" | "PUT" | "DELETE"
--     endpoint: string - API endpoint (e.g., "/users/@me")
--     options: table - optional headers, body, etc.
--     Returns: response table or throws HTTPException
--
--   Client:get(endpoint, options) -> response
--     GET request wrapper.
--
--   Client:post(endpoint, body, options) -> response
--     POST request wrapper.
--
--   Client:put(endpoint, body, options) -> response
--     PUT request wrapper.
--
--   Client:delete(endpoint) -> response
--     DELETE request wrapper.
--
--   Client:parse_json(response) -> table
--     Parses JSON response. Throws HTTPException on error.
--
--   Client:throw_error(status, data) -> exception
--     Creates appropriate error based on status code.

local class = require("core.class")
local errors = require("core.errors")
local json = require("json")

-- HTTP client class
local Client = class("Client")

-- Create a new HTTP client
function Client.new(token, ratelimiter)
    local self = {
        token = token,
        ratelimiter = ratelimiter or {},
        base_url = "https://discord.com/api/v10",
        headers = {
            ["Authorization"] = "Bot " .. token,
            ["Content-Type"] = "application/json",
            ["User-Agent"] = "discord.lua",
        },
    }
    setmetatable(self, {
        __index = Client
    })
    return self
end

-- Helper: parse JSON response
function Client:parse_json(response)
    local success, result = pcall(json.decode, response)
    if not success then
        error("Failed to parse JSON: " .. response, 0)
    end
    return result
end

-- Helper: throw appropriate error based on response
function Client:throw_error(status, data)
    if status == 429 then
        local retry_after = data and data.retry_after or 0
        return errors.RateLimited.new("Rate limited by Discord", retry_after)
    elseif status == 404 then
        return errors.NotFound.new("Resource not found", data and data.id)
    elseif status == 403 then
        return errors.Forbidden.new("Permission denied")
    elseif status >= 500 then
        return errors.HTTPException.new("Internal server error", status, data)
    else
        return errors.HTTPException.new("HTTP error: " .. status, status, data)
    end
end

-- Generic request method
function Client:request(method, endpoint, options)
    local headers = self.headers

    -- Add custom headers
    if options and options.headers then
        for k, v in pairs(options.headers) do
            headers[k] = v
        end
    end

    -- Add body if provided
    local request_body = nil
    if options and options.body then
        if type(options.body) == "table" then
            request_body = json.encode(options.body)
            headers["Content-Type"] = "application/json"
        else
            request_body = tostring(options.body)
        end
    end

    -- Build URL
    local url = self.base_url .. endpoint

    -- Make request using coro-http
    local http = require("http")
    local response, err = http.request(url, {
        method = method,
        headers = headers,
        body = request_body,
    })

    if not response then
        error("Request failed: " .. tostring(err), 0)
    end

    -- Check status code
    local status = response.status
    local body = response.body

    if status >= 400 then
        return self:throw_error(status, body)
    end

    -- Parse JSON response
    local parsed
    local success, result = pcall(json.decode, response.body)
    if not success then
        -- Not JSON, return as string
        parsed = response.body
    else
        parsed = result
    end

    return parsed
end

-- GET wrapper
function Client:get(endpoint, options)
    return self:request("GET", endpoint, options)
end

-- POST wrapper
function Client:post(endpoint, body, options)
    return self:request("POST", endpoint, { body = body, options = options })
end

-- PUT wrapper
function Client:put(endpoint, body, options)
    return self:request("PUT", endpoint, { body = body, options = options })
end

-- DELETE wrapper
function Client:delete(endpoint, options)
    return self:request("DELETE", endpoint, options)
end

-- Check rate limit and wait if necessary
function Client:check_rate_limit(endpoint)
    if self.ratelimiter and self.ratelimiter:is_rate_limited(endpoint) then
        local retry_after = self.ratelimiter:get_retry_after(endpoint)
        coroutine.yield("Rate limited, waiting " .. retry_after .. "s")
        return true
    end
    return false
end

-- Update rate limit from response headers
function Client:update_rate_limit(endpoint, headers)
    if self.ratelimiter then
        self.ratelimiter:update_bucket(endpoint, headers)
    end
end

-- Update global rate limit
function Client:update_global_rate_limit(headers)
    if self.ratelimiter then
        self.ratelimiter:update_global(headers)
    end
end

return Client
