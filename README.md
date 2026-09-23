# extra-lazy.nvim

Enhanced editor mode for LazyVim for (extra) lazy people like me.

Inspired by [micro](https://github.com/zyedidia/micro), [ox](https://github.com/curlpipe/ox) and [novim](https://github.com/link2004/novim).

## Features

- Type-to-insert — Start in insert mode; press any printable character in normal mode to insert it
- Visual mode replace — Select text and type to replace it
- Ctrl shortcuts — Save (`Ctrl+S`), Quit (`Ctrl+Q`), Undo/Redo (`Ctrl+Z`/`Ctrl+Y`), Select All (`Ctrl+A`), and more
- Mouse support — Click, double-click, selection with system clipboard integration
- Arrow-key selection — `Shift+Arrow` to select text in any mode
- Changed-line highlighting — Green gutter highlights for lines modified since last save
- Statusline hints — Dynamic helper text showing available shortcuts

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
| `Ctrl+D` (normal/insert) | Delete line |
| `Ctrl+D` (visual) | Delete selection without changing registers |
| `Ctrl+G` | Go to line |
| `Ctrl+K` | Command line |
| `Esc Esc` | Quick quit |
| `Shift+←→↑↓` | Select text |
| `Ctrl+←` / `Ctrl+→` | Move by word |
| `Ctrl+Backspace` | Delete word backward |
| `Ctrl+Delete` | Delete word forward |
| `Ctrl+C` | Copy (visual mode) |
| `Ctrl+X` | Cut (visual mode) |
| `Ctrl+V` | Paste |

## Configuration

Defaults shown; pass only what you want to change:

```lua
require("extra-lazy").setup({
  -- Editor options applied at setup (any vim option)
  options = {
    mouse = "a",
    mousemodel = "extend",
    clipboard = "unnamedplus",
    showmode = false,
    virtualedit = "onemore",
  },
  -- Individual feature toggles
  mouse_double_click = true,   -- double-click opens files in netrw
  changed_lines = "DiffAdd",   -- highlight group for changed lines; false to disable
  hints = {                    -- statusline hint text (false to disable)
    visual = "^C Copy  ^X Cut  ^A All",
    modified = "^S Save  ^Z Undo  ^Q Quit",
    normal = "^V Paste  ^A All  ^Q Quit",
  },
  type_to_insert = true,       -- start in insert mode; type in normal mode to insert it
  visual_replace = true,       -- type over a visual selection to replace it
  arrow_selection = true,      -- Shift+Arrow to select text
  word_movement = true,        -- Ctrl+Arrow word jump, Ctrl+Backspace/Delete word delete
  -- Remap or disable individual shortcuts ("lhs" -> false, or "lhs" -> new key)
  keymaps = {
    ["<C-d>"] = false,         -- restore default scroll half-page
    ["<C-s>"] = "<leader>w",   -- move save elsewhere
    -- keymaps = false disables all plugin keymaps
  },
})
```

Keymap remaps win over type-to-insert, so `["<C-s>"] = "<leader>w"` frees `s` for normal motion again.

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
