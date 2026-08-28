local class = require("../../core/class")
local AudioSource = require("./source")

local PCMVolumeTransformer = class("PCMVolumeTransformer", AudioSource)

local function clamp(value)
    if value > 32767 then
        return 32767
    end
    if value < -32768 then
        return -32768
    end
    return value
end

function PCMVolumeTransformer.new(original, volume)
    if type(original) ~= "table" or type(original.read) ~= "function" then
        error("PCMVolumeTransformer requires an AudioSource", 0)
    end
    if original.is_opus and original:is_opus() then
        error("PCMVolumeTransformer cannot transform an Opus source", 0)
    end

    local self = setmetatable(AudioSource.new(), PCMVolumeTransformer)
    self.original = original
    self.volume = volume == nil and 1.0 or volume
    if type(self.volume) ~= "number" or self.volume < 0 then
        error("PCMVolumeTransformer volume must be a non-negative number", 0)
    end
    return self
end

function PCMVolumeTransformer:read()
    local data, status = self.original:read()
    if not data then
        return nil, status
    end

    local output = {}
    for i = 1, #data - 1, 2 do
        local sample = data:byte(i) + data:byte(i + 1) * 256
        if sample >= 32768 then
            sample = sample - 65536
        end
        local scaled = sample * self.volume
        if scaled >= 0 then
            sample = math.floor(scaled + 0.5)
        else
            sample = math.ceil(scaled - 0.5)
        end
        sample = clamp(sample)
        if sample < 0 then
            sample = sample + 65536
        end
        output[#output + 1] = string.char(sample % 256, math.floor(sample / 256))
    end
    if #data % 2 == 1 then
        output[#output + 1] = data:sub(-1)
    end
    return table.concat(output)
end

function PCMVolumeTransformer:is_playing()
    return self.original:is_playing()
end

function PCMVolumeTransformer:is_opus()
    return false
end

function PCMVolumeTransformer:cleanup()
    if self.original.cleanup then
        self.original:cleanup()
    end
end

return PCMVolumeTransformer
