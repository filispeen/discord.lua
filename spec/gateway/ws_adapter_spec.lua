-- spec/gateway/ws_adapter_spec.lua
-- Tests for the coro-websocket -> EventEmitter adapter, in particular that
-- ws:send/ws:close never call the underlying coroutine write function
-- directly from the caller's stack, since a raw uv timer callback (e.g.
-- Shard's heartbeat) runs outside any coroutine and would otherwise crash
-- with "cannot resume running coroutine" if the connection's own read
-- coroutine happened to be active at the same time.

require("spec_helper")

local ws_adapter = require("./gateway/ws_adapter")

describe("ws_adapter", function()
    it("send does not run the write function on the caller's coroutine", function()
        local write_ran_in_new_coroutine = false
        local caller_coroutine = coroutine.running()

        local function fake_write(_)
            write_ran_in_new_coroutine = (coroutine.running() ~= caller_coroutine)
        end

        local function fake_read()
            return nil
        end

        local ws = ws_adapter.wrap({}, fake_read, fake_write)
        ws:send("hello")

        assert.is_true(write_ran_in_new_coroutine)
    end)

    it("send survives being called while another coroutine tied to the same connection is already running", function()
        local resumable = coroutine.create(function()
            coroutine.yield()
        end)
        coroutine.resume(resumable)

        local write_called = false
        local function fake_write(_)
            write_called = true
            if coroutine.status(resumable) == "suspended" then
                coroutine.resume(resumable)
            end
        end
        local function fake_read()
            return nil
        end

        local ws = ws_adapter.wrap({}, fake_read, fake_write)

        assert.has_no.errors(function()
            ws:send("heartbeat")
        end)
        assert.is_true(write_called)
    end)

    it("close marks the socket closed and does not raise even if write errors", function()
        local function fake_write()
            error("simulated write failure")
        end
        local function fake_read()
            return nil
        end

        local ws = ws_adapter.wrap({}, fake_read, fake_write)

        assert.has_no.errors(function()
            ws:close()
        end)
        assert.is_true(ws._closed)
    end)

    it("send is a no-op after close", function()
        local write_calls = 0
        local function fake_write(_)
            write_calls = write_calls + 1
        end
        local function fake_read()
            return nil
        end

        local ws = ws_adapter.wrap({}, fake_read, fake_write)
        ws:close()
        local calls_after_close = write_calls
        ws:send("should not send")

        assert.are.equal(calls_after_close, write_calls)
    end)
end)
