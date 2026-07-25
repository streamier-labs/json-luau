--!strict
local JSON = require("../src/main")

-- Primitives & Escapes
assert(JSON.decode("true") == true, "Failed decoding true")
assert(JSON.decode("false") == false, "Failed decoding false")
assert(JSON.decode("null") == nil, "Failed decoding null")
assert(JSON.decode("123.45") == 123.45, "Failed decoding float")
assert(JSON.decode('"hello\\nworld"') == "hello\nworld", "Failed decoding string escape")
assert(JSON.decode('"\\u0041"') == "A", "Failed decoding unicode escape")

-- Arrays & Objects
local arr = JSON.decode("[1, 2, 3]") :: { number }
assert(arr[1] == 1 and arr[2] == 2 and arr[3] == 3, "Failed decoding array")

local obj = JSON.decode('{"name": "Luau", "count": 10}') :: { [string]: any }
assert(obj.name == "Luau" and obj.count == 10, "Failed decoding object")

-- Syntax Error Checks
local okUnclosed = pcall(function()
	JSON.decode('"unclosed string')
end)
assert(not okUnclosed, "Decoder should fail on unclosed string")

local okTrailing = pcall(function()
	JSON.decode('{"a": 1} extra')
end)
assert(not okTrailing, "Decoder should fail on trailing data")

local okComma = pcall(function()
	JSON.decode("[1, 2,]")
end)
assert(not okComma, "Decoder should fail on trailing comma")

return {}
