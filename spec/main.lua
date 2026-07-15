-- spec/main.lua
-- Main test runner for busted

-- Setup package path
package.path = "lib/?.lua;lib/?/?.lua;" .. package.path

-- Load busted
local busted = require("busted")
local describe, it, assert = busted.describe, busted.it, busted.assert
