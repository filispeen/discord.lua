-- Mock luv for testing
local mock_luv = {
    timer = {
        new = function()
            local timer = {
                start = function() end,
                stop = function() end,
            }
            return timer
        end
    },
    now = function() return 0 end,
}

return mock_luv
