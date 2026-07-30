-- lib/core/luv_compat.lua
-- Resolves the libuv binding module across different luvit/luvi builds.
--
-- Public Contract:
--   require("./core/luv_compat") -> the libuv binding table
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
local mock = package.loaded["mock_luv"]
if mock then
    return mock
end

local ok, mod = pcall(require, "luv")
if ok then
    return mod
end

return require("uv")
