require("spec_helper")

local created = {}

local mock_luv = {
    new_pipe = function()
        local pipe = {
            closed = false,
            stopped = false,
        }
        function pipe:read_start(callback)
            self.callback = callback
        end
        function pipe:read_stop()
            self.stopped = true
        end
        function pipe:close()
            self.closed = true
        end
        table.insert(created.pipes, pipe)
        return pipe
    end,
    spawn = function(executable, options, on_exit)
        created.executable = executable
        created.options = options
        created.on_exit = on_exit
        local process = {
            killed = nil,
            closed = false,
        }
        function process:kill(signal)
            self.killed = signal
        end
        function process:close()
            self.closed = true
        end
        created.process = process
        created.stdout = options.stdio[2]
        created.stderr = options.stdio[3]
        return process, 42
    end,
}

local function load_source()
    created = { pipes = {} }
    package.loaded["mock_luv"] = mock_luv
    package.loaded["./core/luv_compat"] = nil
    package.loaded["./voice/sources/ffmpeg_audio_source"] = nil
    return require("./voice/sources/ffmpeg_audio_source")
end

describe("FFmpegAudioSource", function()
    after_each(function()
        package.loaded["mock_luv"] = nil
        package.loaded["./core/luv_compat"] = nil
        package.loaded["./voice/sources/ffmpeg_audio_source"] = nil
        package.loaded["../native_lib"] = nil
    end)

    it("spawns ffmpeg with PCM output arguments", function()
        local FFmpegPCMSource = load_source()
        local source = FFmpegPCMSource.new("song.mp3", {
            executable = "custom-ffmpeg",
            before_options = { "-reconnect", "1" },
            options = { "-vn" },
        })

        assert.equals("custom-ffmpeg", created.executable)
        assert.same({
            "-reconnect", "1", "-i", "song.mp3", "-f", "s16le", "-ar", "48000",
            "-ac", "2", "-loglevel", "warning", "-vn", "pipe:1",
        }, created.options.args)
        assert.equals(42, source.pid)
    end)

    it("passes an HTTPS source URL to FFmpeg unchanged", function()
        local FFmpegPCMSource = load_source()
        FFmpegPCMSource.new("https://audio.example.test/track.mp3")

        assert.equals("https://audio.example.test/track.mp3", created.options.args[2])
    end)

    it("adds the bundled Windows DLL directory to PATH", function()
        package.loaded["../native_lib"] = {
            resolve_executable = function() return "bundled-ffmpeg.exe" end,
            windows_dll_env = function() return { "PATH=bundle-dll-path" } end,
        }

        local FFmpegPCMSource = load_source()
        FFmpegPCMSource.new("song.mp3")

        assert.equals("bundled-ffmpeg.exe", created.executable)
        assert.same({ "PATH=bundle-dll-path" }, created.options.env)
    end)

    it("returns pending before ffmpeg produces a complete frame", function()
        local FFmpegPCMSource = load_source()
        local source = FFmpegPCMSource.new("song.mp3")

        local chunk, state = source:read()

        assert.is_nil(chunk)
        assert.equals("pending", state)
        assert.is_true(source:is_playing())
    end)

    it("returns exact 20ms PCM frames from stdout", function()
        local FFmpegPCMSource = load_source()
        local source = FFmpegPCMSource.new("song.mp3")
        local frame = string.rep("a", 3840)

        created.stdout.callback(nil, frame .. "tail")

        assert.equals(frame, source:read())
        assert.equals("tail", source._buffer)
    end)

    it("waits for the configured prebuffer before starting playback", function()
        local FFmpegPCMSource = load_source()
        local source = FFmpegPCMSource.new("song.mp3", { prebuffer_frames = 2 })

        created.stdout.callback(nil, string.rep("a", 3840))
        assert.is_false(source:is_ready())

        created.stdout.callback(nil, string.rep("a", 3840))
        assert.is_true(source:is_ready())
    end)

    it("pauses and resumes pipe reads around its buffer limits", function()
        local FFmpegPCMSource = load_source()
        local source = FFmpegPCMSource.new("song.mp3", { prebuffer_frames = 1 })

        created.stdout.callback(nil, string.rep("a", 3840 * 100))
        assert.is_true(source._paused_read)

        for _ = 1, 50 do
            source:read()
        end

        assert.is_false(source._paused_read)
        assert.equals(source._on_stdout_read, created.stdout.callback)
    end)

    it("stops after stdout closes with an incomplete trailing frame", function()
        local FFmpegPCMSource = load_source()
        local source = FFmpegPCMSource.new("song.mp3")

        created.stdout.callback(nil, string.rep("a", 3839))
        created.stdout.callback(nil, nil)

        assert.is_nil(source:read())
        assert.is_false(source:is_playing())
    end)

    it("cleans up pipes and terminates the child process once", function()
        local FFmpegPCMSource = load_source()
        local source = FFmpegPCMSource.new("song.mp3")

        source:cleanup()
        source:cleanup()

        assert.equals("sigterm", created.process.killed)
        assert.is_true(created.stdout.stopped)
        assert.is_true(created.stdout.closed)
        assert.is_true(created.stderr.stopped)
        assert.is_true(created.stderr.closed)
    end)

    it("errors when source is missing", function()
        local FFmpegPCMSource = load_source()

        assert.has_error(function()
            FFmpegPCMSource.new()
        end)
    end)
end)
