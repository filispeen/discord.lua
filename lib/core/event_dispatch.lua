local M = {}

function M.run(callback, args, report)
    coroutine.wrap(function()
        local ok, err = pcall(callback, unpack(args, 1, args.n))
        if not ok then report(err) end
    end)()
end

return M
