# neorg-indent

Neorg module for hierarchical indentation of norg files.

## Features

- **Heading indentation** — content under headings is indented based on heading depth
- **List indentation** — unordered (`-`) and ordered (`--`) lists indent according to nesting level
- **Continuation line alignment** — wrapped lines in list items align with the content start

## Installation

Install Neorg (via your Neovim plugin manager) first. This rockspec does not pull Neorg from LuaRocks, so it will rely on your local Neorg checkout.

Install with LuaRocks from the rockspec:

```sh
luarocks make --local neorg-indent-scm-1.rockspec
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

Run tests:

```sh
make test
```

By default the tests look for Neorg under:

```sh
~/.local/share/nvim/lazy/neorg/lua
```

Override with `NEORG_DIR` if your Neorg install lives elsewhere:

```sh
NEORG_DIR=/path/to/neorg/lua make test
```

If `nvim-treesitter` is not under the standard Lazy path, set:

```sh
NVIM_TREESITTER_DIR=/path/to/nvim-treesitter make test
```

Check formatting:

```sh
make format
```

## License

MIT
