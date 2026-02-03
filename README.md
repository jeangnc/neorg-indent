# neorg-indent

Neorg module for hierarchical indentation of norg files.

## Features

- **Heading indentation** — content under headings is indented based on heading depth
- **List indentation** — unordered (`-`) and ordered (`--`) lists indent according to nesting level
- **Continuation line alignment** — wrapped lines in list items align with the content start
- **Batched rendering** — buffer updates are batched via `vim.schedule()` to avoid redundant work

## Installation

Install with LuaRocks:

```sh
luarocks install neorg-indent
```

Then load the module in your Neorg config:

```lua
require("neorg").setup({
    load = {
        ["core.defaults"] = {},
        ["external.indent"] = {},
    },
})
```

## Configuration

| Option            | Default | Description                          |
| ----------------- | ------- | ------------------------------------ |
| `indent_per_level`| `4`     | Number of spaces per indentation level |

```lua
["external.indent"] = {
    config = {
        indent_per_level = 4,
    },
},
```

## Development

Install dependencies:

```sh
make deps
```

Run tests:

```sh
make test
```

Check formatting:

```sh
make format
```

## License

MIT
