# reader.nvim

A distraction-free ebook reader for Neovim. Highlights the current paragraph and dims the rest. Supports `.md`, `.txt`, and `.epub` files.

## Demo

<video src="https://github.com/user-attachments/assets/3d85d123-cb9c-4d13-9c52-29398e1ea69f" controls="controls" width="100%"></video>

## Features

- Paragraph-level focus highlighting with dimmed surroundings
- EPUB support with chapter navigation and table of contents
- Zen-mode style centered floating window layout
- Cursor auto-hides on blank lines between paragraphs
- User bookmarks with navigation (`]b`/`[b`) and picker (`M`)
- Inline notes as ghost text (select text, press `n`, type your note)
- Text highlighting with visual selection
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

" Bookmarks
:ReaderMark              " Add a bookmark at current position
:ReaderMarks             " Show bookmarks picker
:ReaderMarkDelete        " Remove a bookmark

" Notes (displayed as ghost text)
:ReaderNote              " Add a note at current position
:ReaderNotes             " Show notes picker
:ReaderNoteDelete        " Remove a note

" Highlights (select text in visual mode)
:ReaderHighlights        " Show highlights picker
:ReaderHighlightDelete   " Remove a highlight
```

## Keybindings

All standard vim motions work (`j`, `k`, `gg`, `G`, `Ctrl-d`, `Ctrl-u`, `/`, etc.). The following are buffer-local bindings active in reader mode:

| Key | Action |
|-----|--------|
| `q` | Close reader mode |
| `]c` | Next chapter (epub) |
| `[c` | Previous chapter (epub) |
| `t` | Table of contents (epub) |
| `m` | Add a bookmark |
| `dm` | Remove a bookmark |
| `]b` | Jump to next bookmark |
| `[b` | Jump to previous bookmark |
| `M` | Show bookmarks picker |
| `n` | Add a note at selection (visual mode) |
| `dn` | Remove a note |
| `]n` | Jump to next note |
| `[n` | Jump to previous note |
| `N` | Show notes picker |
| `gn` | Toggle notes visibility |
| `s` | Highlight selected text (visual mode) |
| `ds` | Remove a highlight |
| `]s` | Jump to next highlight |
| `[s` | Jump to previous highlight |
| `S` | Show highlights picker |

## Configuration

```lua
require("reader").setup({
  -- Reading pane width in columns
  width = 80,

  -- Zen mode: centered floating window (true) or standard window (false)
  zen_mode = true,

  -- Center the focused paragraph in the viewport
  center_focus = true,

  -- Cursor hiding: "whitespace" (hide on blank lines), "always", or false
  hide_cursor = "whitespace",

  -- Show notes ghost text on open (toggle with gn)
  show_notes = true,

  -- Keybindings (set any to false to disable)
  keys = {
    quit = "q",
    toc = "t",
    next_chapter = "]c",
    prev_chapter = "[c",
    add_mark = "m",
    remove_mark = "dm",
    next_mark = "]b",
    prev_mark = "[b",
    list_marks = "M",
    add_note = "n",
    remove_note = "dn",
    next_note = "]n",
    prev_note = "[n",
    list_notes = "N",
    toggle_notes = "gn",
    add_highlight = "s",
    remove_highlight = "ds",
    next_highlight = "]s",
    prev_highlight = "[s",
    list_highlights = "S",
  },
})
```

## How It Works

- **Paragraph focus**: A `CursorMoved` autocmd detects which paragraph the cursor is in and applies extmark highlights to dim everything else.
- **EPUB parsing**: EPUBs are unzipped via the system `unzip` command. Chapter structure comes from the NCX (EPUB2) or nav document (EPUB3) table of contents. Parsed content is cached to `~/.cache/nvim/reader.nvim/`.
- **Position memory**: Reading position (chapter + line) is saved to `~/.local/share/nvim/reader.nvim/bookmarks.lua` on close and restored on reopen.
- **Layout**: Uses two floating windows (a full-screen backdrop + a centered content window) for a clean, separator-free reading experience.
