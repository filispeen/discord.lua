require("spec_helper")

local PCMVolumeTransformer = require("./voice/sources/pcm_volume_transformer")

local function source(data, opus)
    return {
        read = function(self)
            if self.done then return nil end
            self.done = true
            return data
        end,
        is_playing = function(self) return not self.done end,
        is_opus = function() return opus end,
        cleanup = function(self) self.cleaned = true end,
    }
end

describe("PCMVolumeTransformer", function()
    it("scales signed little-endian PCM samples", function()
        local original = source(string.char(0, 64, 0, 192))
        local transformed = PCMVolumeTransformer.new(original, 0.5)

        assert.equals(string.char(0, 32, 0, 224), transformed:read())
        assert.is_nil(transformed:read())
    end)

    it("clamps amplified samples", function()
        local transformed = PCMVolumeTransformer.new(source(string.char(255, 127)), 2)

        assert.equals(string.char(255, 127), transformed:read())
    end)

    it("rejects Opus input", function()
        assert.has_error(function()
            PCMVolumeTransformer.new(source("", true))
        end)
    end)
end)
