local class = require("../../core/class")
local luv = require("../../core/luv_compat")
local AudioSource = require("./source")

local FFmpegPCMSource = class("FFmpegPCMSource", AudioSource)

local FRAME_BYTES = 960 * 2 * 2

local function append_args(target, value)
    if value == nil then
        return
    end
    if type(value) ~= "table" then
        error("FFmpegPCMSource options must be argument arrays", 0)
    end
    for _, arg in ipairs(value) do
        table.insert(target, tostring(arg))
    end
end

function FFmpegPCMSource.new(source, opts)
    opts = opts or {}
    if type(source) ~= "string" or source == "" then
        error("FFmpegPCMSource requires a non-empty source string", 0)
    end

    local self = setmetatable(AudioSource.new(), FFmpegPCMSource)
    self._buffer = ""
    self._running = true
    self._stdout_closed = false
    self._cleaned = false
    self._error = nil
    self._stderr = ""
    self._process = nil

    local args = {}
    append_args(args, opts.before_options)
    table.insert(args, "-i")
    table.insert(args, source)
    table.insert(args, "-f")
    table.insert(args, "s16le")
    table.insert(args, "-ar")
    table.insert(args, "48000")
    table.insert(args, "-ac")
    table.insert(args, "2")
    table.insert(args, "-loglevel")
    table.insert(args, opts.loglevel or "warning")
    append_args(args, opts.options)
    table.insert(args, "pipe:1")

    local stdout = luv.new_pipe(false)
    local stderr = luv.new_pipe(false)
    self._stdout = stdout
    self._stderr_pipe = stderr

    local process, pid_or_err = luv.spawn(opts.executable or "ffmpeg", {
        args = args,
        stdio = { nil, stdout, stderr },
    }, function(code, signal)
        self._running = false
        self._exit_code = code
        self._exit_signal = signal
        if self._process then
            self._process:close()
            self._process = nil
        end
    end)

    if not process then
        if stdout.close then stdout:close() end
        if stderr.close then stderr:close() end
        error("FFmpegPCMSource failed to spawn " .. tostring(opts.executable or "ffmpeg") .. ": " .. tostring(pid_or_err), 0)
    end

    self._process = process
    self.pid = pid_or_err

    stdout:read_start(function(err, data)
        if err then
            self._error = err
            self._running = false
        end
        if data then
            self._buffer = self._buffer .. data
        else
            self._stdout_closed = true
            self._running = false
        end
    end)

    stderr:read_start(function(_, data)
        if data and #self._stderr < 16384 then
            self._stderr = self._stderr .. data
        end
    end)

    return self
end

function FFmpegPCMSource:read()
    if #self._buffer >= FRAME_BYTES then
        local chunk = self._buffer:sub(1, FRAME_BYTES)
        self._buffer = self._buffer:sub(FRAME_BYTES + 1)
        return chunk
    end

    if self._running then
        return nil, "pending"
    end

    self:cleanup()
    return nil
end

function FFmpegPCMSource:is_playing()
    return self._running or #self._buffer >= FRAME_BYTES
end

function FFmpegPCMSource:cleanup()
    if self._cleaned then
        return
    end
    self._cleaned = true
    self._running = false

    if self._process then
        pcall(function()
            self._process:kill("sigterm")
        end)
        self._process = nil
    end

    if self._stdout then
        pcall(function()
            self._stdout:read_stop()
            self._stdout:close()
        end)
        self._stdout = nil
    end

    if self._stderr_pipe then
        pcall(function()
            self._stderr_pipe:read_stop()
            self._stderr_pipe:close()
        end)
        self._stderr_pipe = nil
    end

    self._buffer = ""
end

return FFmpegPCMSource
