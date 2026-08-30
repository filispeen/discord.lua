local class = require("../../core/class")
local luv = require("../../core/luv_compat")
local AudioSource = require("./source")
local OggStream = require("../oggparse")
local native_lib = require("../native_lib")

local FFmpegOpusSource = class("FFmpegOpusSource", AudioSource)

local function append_args(target, value)
    if value == nil then
        return
    end
    if type(value) ~= "table" then
        error("FFmpegOpusSource options must be argument arrays", 0)
    end
    for _, arg in ipairs(value) do
        target[#target + 1] = tostring(arg)
    end
end

local function parse_probe(data)
    local codec = data:match("codec_name=([^\r\n]+)")
    local bitrate = tonumber(data:match("bit_rate=(%d+)"))
    if bitrate then
        bitrate = math.floor(bitrate / 1000)
    end
    return codec, bitrate
end

function FFmpegOpusSource.new(source, opts)
    opts = opts or {}
    if opts.pipe then
        source = "pipe:0"
    elseif type(source) ~= "string" or source == "" then
        error("FFmpegOpusSource requires a non-empty source string", 0)
    end

    local self = setmetatable(AudioSource.new(), FFmpegOpusSource)
    self._packets = {}
    self._ogg = OggStream.new()
    self._running = true
    self._cleaned = false
    self._stderr = ""
    self._process = nil
    self._stdin = nil

    local codec = opts.codec
    if codec == "opus" or codec == "libopus" or codec == "copy" then
        codec = "copy"
    else
        codec = "libopus"
    end

    local args = {}
    append_args(args, opts.before_options)
    args[#args + 1] = "-i"
    args[#args + 1] = source
    args[#args + 1] = "-map_metadata"
    args[#args + 1] = "-1"
    args[#args + 1] = "-f"
    args[#args + 1] = "opus"
    args[#args + 1] = "-c:a"
    args[#args + 1] = codec
    args[#args + 1] = "-ar"
    args[#args + 1] = "48000"
    args[#args + 1] = "-ac"
    args[#args + 1] = "2"
    args[#args + 1] = "-b:a"
    args[#args + 1] = tostring(opts.bitrate or 128) .. "k"
    args[#args + 1] = "-loglevel"
    args[#args + 1] = opts.loglevel or "warning"
    args[#args + 1] = "-fec"
    args[#args + 1] = "true"
    args[#args + 1] = "-packet_loss"
    args[#args + 1] = "15"
    append_args(args, opts.options)
    args[#args + 1] = "pipe:1"

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
        error("FFmpegOpusSource failed to spawn " .. tostring(executable) .. ": " .. tostring(pid_or_err), 0)
    end

    self._process = process
    self.pid = pid_or_err

    stdout:read_start(function(err, data)
        if err then
            self._error = err
            self._running = false
        end
        if data then
            local ok, parse_err = pcall(function()
                self._ogg:feed(data)
                while true do
                    local packet = self._ogg:next_packet()
                    if not packet then
                        break
                    end
                    if packet:sub(1, 8) ~= "OpusHead" and packet:sub(1, 8) ~= "OpusTags" then
                        self._packets[#self._packets + 1] = packet
                    end
                end
            end)
            if not ok then
                self._error = parse_err
                self._running = false
            end
        else
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

function FFmpegOpusSource:write(data, callback)
    if not self._stdin then
        return false, "FFmpegOpusSource was not created with pipe=true"
    end
    self._stdin:write(data, callback)
    return true
end

function FFmpegOpusSource:close_input(callback)
    if self._stdin and self._stdin.shutdown then
        self._stdin:shutdown(callback)
    end
end

function FFmpegOpusSource:read()
    if #self._packets > 0 then
        return table.remove(self._packets, 1)
    end
    if self._running then
        return nil, "pending"
    end
    self:cleanup()
    return nil
end

function FFmpegOpusSource:is_playing()
    return self._running or #self._packets > 0
end

function FFmpegOpusSource:is_opus()
    return true
end

function FFmpegOpusSource:cleanup()
    if self._cleaned then
        return
    end
    self._cleaned = true
    self._running = false

    if self._process then
        pcall(function() self._process:kill("sigterm") end)
        self._process = nil
    end

    for _, name in ipairs({ "_stdin", "_stdout", "_stderr_pipe" }) do
        local handle = self[name]
        if handle then
            pcall(function()
                if handle.read_stop then handle:read_stop() end
                handle:close()
            end)
            self[name] = nil
        end
    end
    self._packets = {}
end

function FFmpegOpusSource.probe(source, callback, opts)
    opts = opts or {}
    if type(source) ~= "string" or source == "" then
        error("FFmpegOpusSource.probe requires a non-empty source string", 0)
    end
    if type(callback) ~= "function" then
        error("FFmpegOpusSource.probe requires a callback", 0)
    end

    local bundled_executable = native_lib.resolve_executable("ffprobe")
    local executable = opts.probe_executable or bundled_executable or "ffprobe"
    local stdout = luv.new_pipe(false)
    local stderr = luv.new_pipe(false)
    local output, errors = "", ""
    local process
    local spawn_options = {
        args = {
            "-v", "error", "-select_streams", "a:0",
            "-show_entries", "stream=codec_name,bit_rate",
            "-of", "default=noprint_wrappers=1", source,
        },
        stdio = { nil, stdout, stderr },
    }
    if bundled_executable and executable == bundled_executable then
        spawn_options.env = native_lib.windows_dll_env()
    end

    process = luv.spawn(executable, spawn_options, function(code)
        if process then process:close() end
        local codec, bitrate = parse_probe(output)
        callback(codec, bitrate, code == 0 and nil or errors)
    end)

    if not process then
        if stdout.close then stdout:close() end
        if stderr.close then stderr:close() end
        callback(nil, nil, "failed to spawn " .. executable)
        return nil
    end

    stdout:read_start(function(_, data)
        if data then output = output .. data end
    end)
    stderr:read_start(function(_, data)
        if data then errors = errors .. data end
    end)
    return process
end

function FFmpegOpusSource.from_probe(source, callback, opts)
    opts = opts or {}
    return FFmpegOpusSource.probe(source, function(codec, bitrate, err)
        if err then
            callback(nil, err)
            return
        end
        local source_opts = {}
        for key, value in pairs(opts) do
            source_opts[key] = value
        end
        source_opts.codec = codec == "opus" and "copy" or nil
        source_opts.bitrate = bitrate or source_opts.bitrate
        callback(FFmpegOpusSource.new(source, source_opts))
    end, opts)
end

return FFmpegOpusSource
