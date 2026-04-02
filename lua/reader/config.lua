local M = {}

M.defaults = {
  -- Reading pane width in columns
  width = 80,
  -- Open in zen mode (centered floating window) or standard window
  zen_mode = true,
  -- Center the focused paragraph in the viewport
  center_focus = true,
  -- Hide cursor on whitespace: "whitespace" (only on blank chars), "always", or false
  hide_cursor = "whitespace",
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
