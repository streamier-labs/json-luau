--!strict
local JSON = require("../src/main")

-- Primitives
assert(JSON.encode(true) == "true", "Failed encoding true")
assert(JSON.encode(false) == "false", "Failed encoding false")
assert(JSON.encode(123) == "123", "Failed encoding integer")
assert(JSON.encode(-45.67) == "-45.67", "Failed encoding float")
assert(JSON.encode("hello\nworld") == '"hello\\nworld"', "Failed encoding escape string")

-- Arrays & Tables
assert(JSON.encode({ 1, 2, 3 }) == "[1,2,3]", "Failed encoding array")
assert(JSON.encode({}) == "{}", "Failed encoding empty table")

-- Error Handling (Checking for expected throws)
local okNaN = pcall(function()
	JSON.encode(0 / 0)
end)
assert(not okNaN, "Encoder should fail on NaN")

local okInf = pcall(function()
	JSON.encode(math.huge)
end)
assert(not okInf, "Encoder should fail on Infinity")

local okBadKey = pcall(function()
	JSON.encode({ [123] = "val" } :: any)
end)
assert(not okBadKey, "Encoder should fail on non-string keys")

return {}
