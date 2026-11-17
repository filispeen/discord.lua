-- lib/core/luv_compat.lua
-- Resolves the libuv binding module across different luvit/luvi builds.
--
-- Public Contract:
--   require("./luv_compat") -> the libuv binding table
--
-- Some luvit/luvi builds expose the binding as require("luv"), others
-- (observed on luvit 2.18.1 / luvi 2.14.0) only expose it as
-- require("uv") and have no "luv" module registered at all, so a plain
-- require("luv") throws instead of returning anything. This tries "luv"
-- first (preserving existing behavior on builds that do have it), then
-- falls back to "uv". package.loaded["mock_luv"] still takes priority
-- over both so busted specs keep working unchanged, they inject their
-- mock via package.loaded["mock_luv"], not by pre-populating "luv" or
-- "uv" in package.loaded.
local function resolve_luv()
    local mock = package.loaded["mock_luv"]
    if mock then
        return mock
    end
    local loaded_luv = package.loaded["luv"]
    if loaded_luv then
        return loaded_luv
    end
    local ok, mod = pcall(require, "luv")
    if ok then
        return mod
    end
    return require("uv")
end

return setmetatable({}, {
    __index = function(_, key)
        return resolve_luv()[key]
    end,
    __newindex = function(_, key, value)
        resolve_luv()[key] = value
    end,
})
