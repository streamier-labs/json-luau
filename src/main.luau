--- @class JSON
--- A lightweight, pure Luau JSON encoder and decoder module adhering to the RFC 8259 specification.
---
--- Supports all primary JSON primitives and data structures with accurate line and column error reporting during parsing.
local JSON = {}

-- ============================================================================
-- TYPE DEFINITIONS
-- ============================================================================

--- Represents any valid JSON-serializable Luau primitive or nested data structure.
---
--- - **Primitives:** `string`, `number`, `boolean`, `nil`
--- - **Structures:** Object/Dictionary `{ [string]: JSONValue }` or Array `{ JSONValue }`
export type JSONValue = string | number | boolean | { [string]: JSONValue } | { JSONValue } | nil

--- Internal state object tracking stream progress during JSON decoding.
---
--- @type ParserState { source: string, cursor: number, length: number }
--- @within JSON
type ParserState = {
	source: string,
	cursor: number,
	length: number,
}

-- ============================================================================
-- SENTINELS & LOOKUPS
-- ============================================================================

--- Immutable sentinel object representing an explicit JSON `null` inside Luau tables.
---
--- In Luau, table keys set to `nil` are deleted. Use `JSON.Null` when you need to retain
--- an explicit `null` field in encoded JSON outputs.
---
--- @prop Null table
--- @within JSON
--- @readonly
---
--- ```luau
--- local tbl = { status = "active", details = JSON.Null }
--- print(JSON.encode(tbl)) --> {"status":"active","details":null}
--- ```
local NULL_TOKEN = table.freeze(setmetatable({}, {
	__tostring = function()
		return "null"
	end,
}))

JSON.Null = NULL_TOKEN

--- Lookup map for escaping standard string control characters according to RFC 8259.
local ESCAPE_CHAR_MAP: { [string]: string } = {
	['"'] = '\\"',
	["\\"] = "\\\\",
	["\b"] = "\\b",
	["\f"] = "\\f",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
}

-- ============================================================================
-- ENCODER IMPLEMENTATION
-- ============================================================================

--- Determines whether a Luau table should be serialized as a JSON Array (`[...]`) or Object (`{...}`).
---
--- Returns `true` only if the table is non-empty and contains dense, sequential integer keys starting at index `1` without gaps.
--- Empty tables (`{}`) return `false` by default, serializing as empty JSON objects (`{}`).
---
--- @param tbl { [any]: any } -- The table structure to inspect.
--- @return boolean -- `true` if the table qualifies as a JSON array; `false` if it should be an object.
local function isArray(tbl: { [any]: any }): boolean
	local count = 0
	for k in tbl do
		if typeof(k) ~= "number" or k < 1 or math.floor(k) ~= k then
			return false
		end
		count += 1
	end

	if count == 0 then
		return false
	end

	--- Verify array density (indices 1..count exist without internal gaps)
	for i = 1, count do
		if tbl[i] == nil then
			return false
		end
	end

	return true
end

--- Escapes special characters and unicode control characters within a Luau string to form a valid JSON string literal.
---
--- @param str string -- The raw input string to escape.
--- @return string -- The escaped, double-quoted JSON string token.
local function escapeString(str: string): string
	local escaped = string.gsub(str, '["\\\b\f\n\r\t]', ESCAPE_CHAR_MAP)
	--- Escape remaining ASCII control characters in range (0x00 - 0x1F) to \u00XX format
	escaped = string.gsub(escaped, "[\1-\31]", function(c)
		return string.format("\\u%04x", string.byte(c))
	end)

	return '"' .. escaped .. '"'
end

--- Encodes a Luau value or table structure into a formatted JSON string.
---
--- ### Type Mapping Matrix:
--- | Luau Data Type | Resulting JSON Format | Special Rules / Notes |
--- | :--- | :--- | :--- |
--- | `nil` / `JSON.Null` | `null` | Encodes explicitly as JSON null literal |
--- | `boolean` | `true` / `false` | Serializes as boolean literal |
--- | `number` | `123.45` | Rejects `NaN` and `±Infinity` |
--- | `string` | `"hello"` | Escapes non-printable & control characters |
--- | `table` (Array) | `[1, 2, 3]` | Dense sequential integer keys `1..N` |
--- | `table` (Object) | `{"key":"val"}` | String-keyed dictionary (empty `{}` outputs `{}`) |
---
--- @param value JSONValue -- The Luau value or nested table to serialize.
--- @return string -- The valid JSON string representation.
--- @error "[JSON.encode] Cannot encode NaN or Infinity to valid JSON" -- Thrown if a number value is non-finite.
--- @error "[JSON.encode] Table key must be a string..." -- Thrown if an object table key is not a string.
--- @error "[JSON.encode] Unsupported type..." -- Thrown if trying to serialize unsupported types (function, thread, userdata).
function JSON.encode(value: JSONValue): string
	local valueType = typeof(value)

	if value == nil or value == JSON.Null then
		return "null"
	elseif valueType == "boolean" then
		return if value then "true" else "false"
	elseif valueType == "number" then
		local num = value :: number
		if num ~= num or num == math.huge or num == -math.huge then
			error("[JSON.encode] Cannot encode NaN or Infinity to valid JSON", 2)
		end
		return tostring(num)
	elseif valueType == "string" then
		return escapeString(value :: string)
	elseif valueType == "table" then
		local tbl = value :: { [any]: any }

		if isArray(tbl) then
			local elements = {}
			for index, val in ipairs(tbl) do
				elements[index] = JSON.encode(val)
			end
			return "[" .. table.concat(elements, ",") .. "]"
		else
			local pairsList = {}
			for k, v in tbl do
				if typeof(k) ~= "string" then
					error("[JSON.encode] Table key must be a string, got: " .. typeof(k), 2)
				end
				table.insert(pairsList, escapeString(k) .. ":" .. JSON.encode(v))
			end
			return "{" .. table.concat(pairsList, ",") .. "}"
		end
	else
		error("[JSON.encode] Unsupported type for JSON serialization: " .. valueType, 2)
	end
end

-- ============================================================================
-- DECODER IMPLEMENTATION
-- ============================================================================

--- Calculates line number and column offset for accurate syntax error locations.
---
--- @param source string -- The original JSON source string.
--- @param cursor number -- The byte position in the source string.
--- @return number -- Line number (1-based index).
--- @return number -- Column number (1-based index).
local function getLineAndColumn(source: string, cursor: number): (number, number)
	local line = 1
	local col = 1
	local maxPos = math.min(cursor, #source)
	for i = 1, maxPos do
		if string.byte(source, i) == 10 then --- ASCII 10 = '\n'
			line += 1
			col = 1
		else
			col += 1
		end
	end
	return line, col
end

--- Raises a syntax error indicating line number, column offset, byte position, and message.
---
--- @param state ParserState -- Active parser state structure.
--- @param message string -- Description of the parse failure.
--- @return never
local function parseError(state: ParserState, message: string): never
	local line, col = getLineAndColumn(state.source, state.cursor)
	error(
		string.format("[JSON.decode] Syntax Error at line %d, col %d (pos %d): %s", line, col, state.cursor, message),
		0
	)
end

--- Fast-forwards the parser cursor past leading JSON whitespace characters (`space`, `tab`, `newline`, `return`).
---
--- @param state ParserState -- Active parser state structure.
local function skipWhitespace(state: ParserState)
	local _, finish = string.find(state.source, "^[ \t\n\r]+", state.cursor)
	if finish then
		state.cursor = finish + 1
	end
end

--- Returns the character at the current parser cursor position without advancing.
---
--- @param state ParserState -- Active parser state structure.
--- @return string -- Single character string at current position, or `""` if cursor exceeds stream length.
local function peek(state: ParserState): string
	if state.cursor > state.length then
		return ""
	end
	return string.sub(state.source, state.cursor, state.cursor)
end

--- Forward declaration for recursive value parsing.
local parseValue: (state: ParserState) -> JSONValue

--- Parses a JSON string literal starting at an opening double quote `"`.
--- Handles standard escapes (`\"`, `\\`, `\/`, `\b`, `\f`, `\n`, `\r`, `\t`) and UTF-8 `\uXXXX` unicode code points.
---
--- @param state ParserState -- Active parser state structure.
--- @return string -- The decoded string.
--- @error "Unterminated string literal" -- Thrown if closing quote is missing.
--- @error "Invalid escape sequence..." -- Thrown if an invalid or malformed escape sequence is encountered.
local function parseString(state: ParserState): string
	state.cursor += 1 --- Consume opening quote `"`
	local source = state.source
	local length = state.length
	local chunks: { string }? = nil

	while state.cursor <= length do
		local finish, _, char = string.find(source, '(["\\])', state.cursor)
		if not finish or not char then
			return parseError(state, "Unterminated string literal")
		end

		if finish > state.cursor then
			local part = string.sub(source, state.cursor, finish - 1)
			if chunks then
				table.insert(chunks, part)
			else
				--- Fast path for strings containing no escape characters
				if char == '"' then
					state.cursor = finish + 1
					return part
				end
				chunks = { part }
			end
		elseif not chunks then
			chunks = {}
		end

		state.cursor = finish + 1

		if char == '"' then
			return table.concat(chunks :: { string })
		end

		--- Handle escape sequence parsing
		if state.cursor > length then
			return parseError(state, "Unexpected end of input in escape sequence")
		end

		local escapeChar = string.sub(source, state.cursor, state.cursor)
		state.cursor += 1

		if escapeChar == '"' or escapeChar == "\\" or escapeChar == "/" then
			table.insert(chunks :: { string }, escapeChar)
		elseif escapeChar == "b" then
			table.insert(chunks :: { string }, "\b")
		elseif escapeChar == "f" then
			table.insert(chunks :: { string }, "\f")
		elseif escapeChar == "n" then
			table.insert(chunks :: { string }, "\n")
		elseif escapeChar == "r" then
			table.insert(chunks :: { string }, "\r")
		elseif escapeChar == "t" then
			table.insert(chunks :: { string }, "\t")
		elseif escapeChar == "u" then
			local hex = string.sub(source, state.cursor, state.cursor + 3)
			if #hex < 4 then
				return parseError(state, "Invalid unicode escape sequence '\\u" .. hex .. "'")
			end
			state.cursor += 4
			local codepoint = tonumber(hex, 16)
			if not codepoint then
				return parseError(state, "Invalid hex digits in unicode escape '\\u" .. hex .. "'")
			end
			table.insert(chunks :: { string }, utf8.char(codepoint))
		else
			return parseError(state, "Invalid escape sequence '\\" .. escapeChar .. "'")
		end
	end

	return parseError(state, "Unterminated string literal")
end

--- Parses a JSON numeric token, supporting integer, decimal, negative, and exponent notation (`e`/`E`).
---
--- @param state ParserState -- Active parser state structure.
--- @return number -- The parsed numerical value.
--- @error "Malformed number" -- Thrown if token cannot be converted to a valid number.
local function parseNumber(state: ParserState): number
	local source = state.source
	local matchStart, matchEnd = string.find(source, "^%-?%d+%.?%d*[eE][%+%-]?%d+", state.cursor)
	if not matchStart or not matchEnd then
		matchStart, matchEnd = string.find(source, "^%-?%d+%.?%d*", state.cursor)
	end

	if not matchStart or not matchEnd then
		return parseError(state, "Malformed number")
	end

	local numStr = string.sub(source, matchStart, matchEnd)
	local num = tonumber(numStr)
	if not num then
		return parseError(state, "Malformed number")
	end

	state.cursor = matchEnd + 1
	return num
end

--- Parses a JSON array token `[...]` into a 1-indexed sequential Luau array table.
---
--- @param state ParserState -- Active parser state structure.
--- @return { JSONValue } -- Luau table array containing parsed elements.
--- @error "Expected ',' or ']'" -- Thrown if array elements are separated incorrectly.
local function parseArray(state: ParserState): { JSONValue }
	state.cursor += 1 --- Consume `[`
	skipWhitespace(state)

	local array = {}
	if peek(state) == "]" then
		state.cursor += 1
		return array
	end

	while true do
		local element = parseValue(state)
		table.insert(array, element)
		skipWhitespace(state)

		local char = peek(state)
		if char == "]" then
			state.cursor += 1
			break
		elseif char == "," then
			state.cursor += 1
		else
			return parseError(state, "Expected ',' or ']' in array, got '" .. char .. "'")
		end
	end

	return array
end

--- Parses a JSON object token `{...}` into a string-keyed Luau dictionary table.
---
--- @param state ParserState -- Active parser state structure.
--- @return { [string]: JSONValue } -- Key-value table mapping parsed JSON properties.
--- @error "Expected string key in object" -- Thrown if non-string key is encountered.
--- @error "Expected ':' after key" -- Thrown if key-value delimiter is missing.
--- @error "Expected ',' or '}'" -- Thrown if object key-value pairs are separated improperly.
local function parseObject(state: ParserState): { [string]: JSONValue }
	state.cursor += 1 --- Consume `{`
	skipWhitespace(state)

	local object = {}
	if peek(state) == "}" then
		state.cursor += 1
		return object
	end

	while true do
		skipWhitespace(state)
		if peek(state) ~= '"' then
			return parseError(state, "Expected string key in object, got '" .. peek(state) .. "'")
		end

		local key = parseString(state)
		skipWhitespace(state)

		if peek(state) ~= ":" then
			return parseError(state, "Expected ':' after key, got '" .. peek(state) .. "'")
		end
		state.cursor += 1 --- Consume `:`

		local value = parseValue(state)
		object[key] = value
		skipWhitespace(state)

		local char = peek(state)
		if char == "}" then
			state.cursor += 1
			break
		elseif char == "," then
			state.cursor += 1
		else
			return parseError(state, "Expected ',' or '}' in object, got '" .. char .. "'")
		end
	end

	return object
end

--- Recursively evaluates and parses the JSON token starting at the current cursor position.
---
--- @param state ParserState -- Active parser state structure.
--- @return JSONValue -- The decoded Luau primitive or nested data structure.
--- @error "Unexpected character" -- Thrown when encountering an unrecognizable token character.
parseValue = function(state: ParserState): JSONValue
	skipWhitespace(state)
	local char = peek(state)

	if char == '"' then
		return parseString(state)
	elseif char == "{" then
		return parseObject(state)
	elseif char == "[" then
		return parseArray(state)
	elseif char == "-" or string.find(char, "%d") ~= nil then
		return parseNumber(state)
	elseif string.sub(state.source, state.cursor, state.cursor + 3) == "true" then
		state.cursor += 4
		return true
	elseif string.sub(state.source, state.cursor, state.cursor + 4) == "false" then
		state.cursor += 5
		return false
	elseif string.sub(state.source, state.cursor, state.cursor + 3) == "null" then
		state.cursor += 4
		return nil
	else
		return parseError(state, "Unexpected character '" .. char .. "'")
	end
end

--- Decodes a JSON string into its equivalent Luau value structure.
---
--- @param jsonString string -- The raw JSON string to decode.
--- @return JSONValue -- The parsed Luau scalar value or nested table structure.
--- @error "[JSON.decode] Syntax Error..." -- Raised with line & column indices on malformed JSON or trailing character data.
---
--- ```luau
--- local data = JSON.decode('{"items": [1, 2, 3], "valid": true}')
--- print(data.items[1]) --> 1
--- ```
function JSON.decode(jsonString: string): JSONValue
	local state: ParserState = {
		source = jsonString,
		cursor = 1,
		length = #jsonString,
	}

	local result = parseValue(state)
	skipWhitespace(state)

	if state.cursor <= state.length then
		return parseError(state, "Unexpected trailing character data after valid JSON")
	end

	return result
end

return JSON
