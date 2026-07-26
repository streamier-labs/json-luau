# JSON.luau

A lightweight, pure Luau JSON encoder and decoder module adhering strictly to the
[RFC 8259 specification](https://www.rfc-editor.org/rfc/rfc8259).

Supports all standard JSON primitives and nested data structures, featuring exact
line and column offset reporting for fast and painless debugging.

______________________________________________________________________

## Features

- **RFC 8259 Compliant:** Full support for strings, numbers, booleans, arrays,
  objects, and `null` values.
- **Detailed Error Tracking:** Clear error messaging indicating exact line,
  column, and byte offset when decoding malformed JSON strings.
- **Explicit `null` Handling:** Includes a sentinel `JSON.Null` value to preserve
  explicit `null` fields in Luau tables.
- **Zero Dependencies:** Pure Luau implementation designed to work seamlessly in
  Luau environments[cite: 1, 3].

______________________________________________________________________

## Installation

Add `streamier/json` to your `pesde.toml` dependencies:

```toml
[dependencies]
json = { name = "streamier/json", version = "^0.1.0" }
```

Or install it via the `pesde` CLI:

```bash
pesde add streamier/json
```

______________________________________________________________________

## Quick Start

```luau
local JSON = require("path/to/json")

-- Encoding
local data = {
    name = "Luau",
    version = 1.0,
    tags = { "language", "scripting" },
    deprecated = JSON.Null,
}

local jsonString = JSON.encode(data)
print(jsonString)
-- Output: {"deprecated":null,"name":"Luau","tags":["language","scripting"],"version":1}

-- Decoding
local decodedData = JSON.decode(jsonString)
print(decodedData.name) --> Luau
print(decodedData.tags[1]) --> language
```

______________________________________________________________________

## API Reference

### `JSON.encode(value: JSONValue): string`

Encodes a Luau value or nested table structure into a formatted JSON string.

#### Type Mapping Matrix

<!-- markdownlint-disable -->
| Luau Data Type      | Resulting JSON Format | Notes                                                                                |
| :------------------ | :-------------------- | :----------------------------------------------------------------------------------- |
| `nil` / `JSON.Null` | `null`                | Serializes as a JSON `null` literal.                                                 |
| `boolean`           | `true` / `false`      | Serializes as a JSON boolean literal.                                                |
| `number`            | `123.45`              | Serializes as a JSON number. Rejects `NaN` and `±Infinity`.                          |
| `string`            | `"hello"`             | Serializes as a JSON string. Automatically escapes control characters and quotes.    |
| `table` (Array)     | `[1, 2, 3]`           | Serializes as a JSON array. Requires dense sequential integer keys (`1..N`).         |
| `table` (Object)    | `{"key": "val"}`      | Serializes as a JSON object with string keys. Empty tables (`{}`) serialize as `{}`. |
<!-- markdownlint-enable -->

> [!CAUTION]
> Encoding non-finite numbers (`NaN`, `math.huge`), non-string table keys,
or unsupported types (`function`, `thread`, `userdata`) will raise an error.

______________________________________________________________________

### `JSON.decode(jsonString: string): JSONValue`

Decodes a valid JSON string into its equivalent Luau value structure.

```luau
local data = JSON.decode('{"items": [1, 2, 3], "valid": true}')
print(data.items[1]) --> 1
```

> [!NOTE]
> Syntax errors provide line, column, and character position details:
> `[JSON.decode] Syntax Error at line 1, col 12 (pos 12): Expected ':' after key`

______________________________________________________________________

### `JSON.Null`

An immutable sentinel object representing
an explicit JSON `null` value inside Luau tables.

Since setting a key's value to `nil` in Luau deletes the key from the table,
use `JSON.Null` to preserve intentional `null` entries:

```luau
local payload = {
    status = "active",
    details = JSON.Null,
}

print(JSON.encode(payload)) --> {"status":"active","details":null}
```

______________________________________________________________________

## Development

If you are contributing or running this repository locally:

### Environment Setup

This repository uses [`devenv`](https://devenv.sh/) for
reproducible development environments with Nix.

```bash
devenv shell
```

### Commands

- **Build:** `pesde run build`
- **Test:** `pesde run test`
- **Format Code:** `treefmt`

______________________________________________________________________

## License

This project is licensed under the [MIT License](LICENSE).
