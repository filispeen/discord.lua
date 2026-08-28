local M = {}

function M.band(a, b)
    a, b = tonumber(a) or 0, tonumber(b) or 0
    local result, place = 0, 1
    while a > 0 or b > 0 do
        local abit, bbit = a % 2, b % 2
        if abit == 1 and bbit == 1 then result = result + place end
        a, b, place = (a - abit) / 2, (b - bbit) / 2, place * 2
    end
    return result
end

function M.bor(a, b)
    a, b = tonumber(a) or 0, tonumber(b) or 0
    local result, place = 0, 1
    while a > 0 or b > 0 do
        local abit, bbit = a % 2, b % 2
        if abit == 1 or bbit == 1 then result = result + place end
        a, b, place = (a - abit) / 2, (b - bbit) / 2, place * 2
    end
    return result
end

function M.bnot(a, width)
    a, width = tonumber(a) or 0, width or 53
    local result, place = 0, 1
    for _ = 1, width do
        local abit = a % 2
        if abit == 0 then result = result + place end
        a, place = (a - abit) / 2, place * 2
    end
    return result
end

return M
