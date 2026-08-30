local class = require("../../core/class")
local luv = require("../../core/luv_compat")
local AudioSource = require("./source")
local native_lib = require("../native_lib")

local FFmpegAudioSource = class("FFmpegAudioSource", AudioSource)

local FRAME_BYTES = 960 * 2 * 2
local DEFAULT_PREBUFFER_FRAMES = 50
local MAX_BUFFER_FRAMES = 100
local RESUME_BUFFER_FRAMES = 50

local function append_args(target, value)
    if value == nil then
        return
    end
    if type(value) ~= "table" then
        error("FFmpegAudioSource options must be argument arrays", 0)
    end
    for _, arg in ipairs(value) do
        table.insert(target, tostring(arg))
    end
end

function FFmpegAudioSource.new(source, opts)
    opts = opts or {}
    if opts.pipe then
        source = "pipe:0"
    elseif type(source) ~= "string" or source == "" then
        error("FFmpegAudioSource requires a non-empty source string", 0)
    end

    local self = setmetatable(AudioSource.new(), FFmpegAudioSource)
    self._buffer = ""
    self._prebuffer_frames = math.max(1, math.floor(opts.prebuffer_frames or DEFAULT_PREBUFFER_FRAMES))
    self._paused_read = false
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

    local stdin = opts.pipe and luv.new_pipe(false) or nil
    local stdout = luv.new_pipe(false)
    local stderr = luv.new_pipe(false)
    self._stdin = stdin
    self._stdout = stdout
    self._stderr_pipe = stderr

    local bundled_executable = native_lib.resolve_executable("ffmpeg")
    local executable = opts.executable or bundled_executable or "ffmpeg"
    local spawn_options = {
        args = args,
        stdio = { stdin, stdout, stderr },
    }
    if bundled_executable and executable == bundled_executable then
        spawn_options.env = native_lib.windows_dll_env()
    end
    local process, pid_or_err = luv.spawn(executable, spawn_options, function(code, signal)
        self._running = false
        self._exit_code = code
        self._exit_signal = signal
        if self._process then
            self._process:close()
            self._process = nil
        end
    end)

    if not process then
        if stdin and stdin.close then stdin:close() end
        if stdout.close then stdout:close() end
        if stderr.close then stderr:close() end
        error("FFmpegAudioSource failed to spawn " .. tostring(executable) .. ": " .. tostring(pid_or_err), 0)
    end

    self._process = process
    self.pid = pid_or_err

    self._on_stdout_read = function(err, data)
        if err then
            self._error = err
            self._running = false
        end
        if data then
            self._buffer = self._buffer .. data
            if #self._buffer >= FRAME_BYTES * MAX_BUFFER_FRAMES then
                stdout:read_stop()
                self._paused_read = true
            end
        else
            self._stdout_closed = true
            self._running = false
        end
    end
    stdout:read_start(self._on_stdout_read)

    stderr:read_start(function(_, data)
        if data and #self._stderr < 16384 then
            self._stderr = self._stderr .. data
        end
    end)

    return self
end

function FFmpegAudioSource:write(data, callback)
    if not self._stdin then
        return false, "FFmpegAudioSource was not created with pipe=true"
    end
    self._stdin:write(data, callback)
    return true
end

function FFmpegAudioSource:close_input(callback)
    if self._stdin and self._stdin.shutdown then
        self._stdin:shutdown(callback)
    end
end

function FFmpegAudioSource:is_opus()
    return false
end

function FFmpegAudioSource:is_ready()
    local frames = math.floor(#self._buffer / FRAME_BYTES)
    return frames >= self._prebuffer_frames or (not self._running and frames > 0)
end

function FFmpegAudioSource:read()
    if #self._buffer >= FRAME_BYTES then
        local chunk = self._buffer:sub(1, FRAME_BYTES)
        self._buffer = self._buffer:sub(FRAME_BYTES + 1)
        if self._paused_read
            and #self._buffer <= FRAME_BYTES * RESUME_BUFFER_FRAMES
            and self._stdout
            and self._on_stdout_read
        then
            self._stdout:read_start(self._on_stdout_read)
            self._paused_read = false
        end
        return chunk
    end

    if self._running then
        return nil, "pending"
    end

    self:cleanup()
    return nil
end

function FFmpegAudioSource:is_playing()
    return self._running or #self._buffer >= FRAME_BYTES
end

function FFmpegAudioSource:cleanup()
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

    if self._stdin then
        pcall(function()
            self._stdin:close()
        end)
        self._stdin = nil
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

return FFmpegAudioSource
