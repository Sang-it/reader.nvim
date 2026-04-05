local M = {}

M.defaults = {
  -- Reading pane width in columns
  width = 80,
  -- Open in zen mode (centered floating window) or standard window
  zen_mode = true,
  -- Highlight current paragraph and dim the rest in zen mode
  focus_paragraph = true,
  -- Dim all text instead of focusing paragraphs
  use_dimtext = false,
  -- Center the focused paragraph in the viewport
  center_focus = true,
  -- Hide cursor on whitespace: "whitespace" (only on blank chars), "always", or false
  hide_cursor = "whitespace",
  -- Show notes ghost text on open
  show_notes = true,
  -- Show text highlights on open
  show_highlights = true,
  -- Auto-open reader for these filetypes on BufEnter (e.g. {"md", "txt", "epub"})
  auto_open = {},
  -- Words per minute for auto-scroll mode
  auto_scroll_wpm = 200,
  -- Keybindings (set to false to disable)
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
    toggle_highlights = "gs",
    dict_lookup = "gd",
    toggle_auto_scroll = "g ",
  },
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

function M.get()
  if vim.tbl_isempty(M.options) then
    M.setup()
  end
  return M.options
end

return M
