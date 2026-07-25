local process = require("@lune/process")

process.exec("darklua", { "process", "src/main.luau", "dist/main.luau" })
