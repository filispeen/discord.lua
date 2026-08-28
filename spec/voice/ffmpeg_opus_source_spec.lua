require("spec_helper")

local created = {}
local mock_luv = {
    new_pipe = function()
        local pipe = {}
        function pipe:read_start(callback) self.callback = callback end
        function pipe:read_stop() self.stopped = true end
        function pipe:close() self.closed = true end
        function pipe:write(data, callback)
            self.written = data
            if callback then callback() end
        end
        function pipe:shutdown(callback)
            self.shutdown_called = true
            if callback then callback() end
        end
        return pipe
    end,
    spawn = function(executable, options, on_exit)
        created.executable = executable
        created.options = options
        created.on_exit = on_exit
        local process = {}
        function process:kill(signal) self.killed = signal end
        function process:close() self.closed = true end
        created.process = process
        created.stdin, created.stdout, created.stderr = options.stdio[1], options.stdio[2], options.stdio[3]
        return process, 42
    end,
}

local function page(packets)
    local lacing, body = {}, {}
    for _, packet in ipairs(packets) do
        lacing[#lacing + 1] = string.char(#packet)
        body[#body + 1] = packet
    end
    return "OggS" .. string.char(0, 0) .. string.rep("\0", 20) ..
        string.char(#lacing) .. table.concat(lacing) .. table.concat(body)
end

local function load_source()
    created = {}
    package.loaded["mock_luv"] = mock_luv
    package.loaded["./core/luv_compat"] = nil
    package.loaded["./voice/oggparse"] = nil
    package.loaded["./voice/sources/ffmpeg_opus_source"] = nil
    return require("./voice/sources/ffmpeg_opus_source")
end

describe("FFmpegOpusSource", function()
    after_each(function()
        package.loaded["mock_luv"] = nil
        package.loaded["./core/luv_compat"] = nil
        package.loaded["./voice/oggparse"] = nil
        package.loaded["./voice/sources/ffmpeg_opus_source"] = nil
    end)

    it("uses copy passthrough and returns Ogg audio packets", function()
        local FFmpegOpusSource = load_source()
        local source = FFmpegOpusSource.new("song.webm", { codec = "opus", bitrate = 96 })

        assert.equals("copy", created.options.args[8])
        created.stdout.callback(nil, page({ "OpusHead", "OpusTags", "audio" }))

        assert.is_true(source:is_opus())
        assert.equals("audio", source:read())
    end)

    it("provides writable stdin for pipe sources", function()
        local FFmpegOpusSource = load_source()
        local source = FFmpegOpusSource.new(nil, { pipe = true })

        assert.equals("pipe:0", created.options.args[2])
        assert.is_true(source:write("input"))
        assert.equals("input", created.stdin.written)
        source:close_input()
        assert.is_true(created.stdin.shutdown_called)
    end)
end)
