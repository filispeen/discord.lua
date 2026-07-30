-- lib/core/json_compat.lua
-- Resolves a JSON encode/decode module across different environments.
--
-- Public Contract:
--   require("./core/json_compat") -> table with .encode(value) / .decode(str)
--
-- Files loaded from disk under lib/ (as opposed to the bundle's own
-- deps/) cannot see luvit/luvi's bundled "json" module, since a
-- require() issued from a filesystem file only looks on the filesystem,
-- never in the bundle (this is the same class of issue luv_compat.lua
-- works around for the libuv binding). This tries "json" first
-- (works when this file itself is loaded from inside the bundle, or on
-- builds where "json" is installed as a real rock), then falls back to
-- "dkjson" (installed via luarocks, used by the busted/plain-Lua test
-- environment already). dkjson exposes the same .encode/.decode
-- contract "json" does, so no adapter is needed.
local ok, mod = pcall(require, "json")
if ok then
    return mod
end

return require("dkjson")
