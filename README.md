# extra-lazy.nvim

Enhanced editor mode for LazyVim — type-to-edit, keyboard-driven workflow, mouse support.

Inspired by [ox](https://github.com/curlpipe/ox) and [novim](https://github.com/link2004/novim).

## Features

- **Type-to-insert** — Press any printable character in normal mode to insert it (no more `i` before typing)
- **Visual mode replace** — Select text and type to replace it
- **Ctrl shortcuts** — Save (`Ctrl+S`), Quit (`Ctrl+Q`), Undo/Redo (`Ctrl+Z`/`Ctrl+Y`), Select All (`Ctrl+A`), and more
- **Mouse support** — Click, double-click, selection with system clipboard integration
- **Arrow-key selection** — `Shift+Arrow` to select text in any mode
- **Changed-line highlighting** — Green gutter highlights for lines modified since last save
- **Statusline hints** — Dynamic helper text showing available shortcuts

## Installation

### lazy.nvim (LazyVim)

```lua
{
  "theoneand33/extra-lazy.nvim",
  lazy = false,
  config = function()
    require("extra-lazy").setup()
  end,
}
```

### Packer

```lua
use {
  "theoneand33/extra-lazy.nvim",
  config = function()
    require("extra-lazy").setup()
  end,
}
```

## Keymaps

| Shortcut | Action |
|---|---|
| `Ctrl+S` | Save file |
| `Ctrl+Q` | Quit (with unsaved warning) |
| `Ctrl+N` | New file |
| `Ctrl+O` | Open file |
| `Ctrl+Z` | Undo |
| `Ctrl+Y` | Redo |
| `Ctrl+A` | Select all |
| `Ctrl+F` | Find in files (Telescope) |
| `Ctrl+R` | Find word under cursor |
| `Ctrl+D` | Delete line |
| `Ctrl+G` | Go to line |
| `Ctrl+K` | Command line |
| `Esc Esc` | Quick quit |
| `Shift+←→↑↓` | Select text |
| `Ctrl+C` | Copy (visual mode) |
| `Ctrl+X` | Cut (visual mode) |
| `Ctrl+V` | Paste |

## Configuration

The plugin is zero-config by design. If you want to disable certain keymaps, you can override them after `setup()`:

```lua
require("extra-lazy").setup()
-- Override any conflicting keymap
vim.keymap.del("n", "<C-d>") -- restore scroll half-page
```

## Statusline Integration

The plugin exposes `extra_lazy_hints()` for use in your statusline:

```lua
require("lualine").setup({
  sections = {
    lualine_x = { extra_lazy_hints },
  },
})
```

## License

MIT
