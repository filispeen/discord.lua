-- spec/main.lua
-- Main test runner for busted

-- Setup package path
require("spec_helper")

-- Load busted
local busted = require("busted")
local describe, it, assert = busted.describe, busted.it, busted.assert
