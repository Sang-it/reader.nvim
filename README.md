# reader.nvim

A distraction-free ebook reader for Neovim. Highlights the current paragraph and dims the rest. Supports `.md`, `.txt`, and `.epub` files.

## Features

- Paragraph-level focus highlighting with dimmed surroundings
- EPUB support with chapter navigation and table of contents
- Zen-mode style centered floating window layout
- Cursor auto-hides on blank lines between paragraphs
- Remembers your reading position per file (chapter + line)
- EPUB parsing is cached for fast reopening
- Normal vim motions for navigation

## Requirements

- Neovim >= 0.10
- `termguicolors` enabled (for cursor hiding)
- `unzip` command available (for EPUB support)

## Installation

### lazy.nvim

```lua
{
  "sangitmanandhar/reader.nvim",
  cmd = "Reader",
  opts = {},
}
```

### packer.nvim

```lua
use {
  "sangitmanandhar/reader.nvim",
  config = function()
    require("reader").setup()
  end,
}
```

## Usage

```vim
:Reader                  " Open current buffer file in reader mode
:Reader path/to/file     " Open a specific file
:ReaderClose             " Close reader mode (or press q)

" EPUB chapter navigation
:ReaderNext              " Next chapter
:ReaderPrev              " Previous chapter
:ReaderGo 5              " Jump to chapter 5
:ReaderToc               " Open table of contents picker
```

## Keybindings

All standard vim motions work (`j`, `k`, `gg`, `G`, `Ctrl-d`, `Ctrl-u`, `/`, etc.). The following are buffer-local bindings active in reader mode:

| Key | Action |
|-----|--------|
| `q` | Close reader mode |
| `]c` | Next chapter (epub) |
| `[c` | Previous chapter (epub) |
| `t` | Table of contents (epub) |

## Configuration

```lua
require("reader").setup({
  -- Reading pane width in columns
  width = 80,

  -- Center the focused paragraph in the viewport
  center_focus = true,

  -- Cursor hiding: "whitespace" (hide on blank lines), "always", or false
  hide_cursor = "whitespace",

  -- Keybindings (set any to false to disable)
  keys = {
    quit = "q",
    toc = "t",
    next_chapter = "]c",
    prev_chapter = "[c",
  },
})
```

## How It Works

- **Paragraph focus**: A `CursorMoved` autocmd detects which paragraph the cursor is in and applies extmark highlights to dim everything else.
- **EPUB parsing**: EPUBs are unzipped via the system `unzip` command. Chapter structure comes from the NCX (EPUB2) or nav document (EPUB3) table of contents. Parsed content is cached to `~/.cache/nvim/reader.nvim/`.
- **Position memory**: Reading position (chapter + line) is saved to `~/.local/share/nvim/reader.nvim/bookmarks.lua` on close and restored on reopen.
- **Layout**: Uses two floating windows (a full-screen backdrop + a centered content window) for a clean, separator-free reading experience.
