local M = {}

local ns = vim.api.nvim_create_namespace("reader_autoscroll")
local timer = nil
local active = false
local current_buf = nil
local word_line = nil -- 0-indexed
local word_idx = nil -- 1-based
local words_on_line = nil -- list of {col_start, col_end}
local parked_line = nil -- 0-indexed blank line to park cursor on
local saved_guicursor = nil

function M.setup_highlights()
  vim.api.nvim_set_hl(0, "ReaderAutoScroll", {
    bold = true,
    underline = true,
    reverse = true,
  })
end

--- Parse word boundaries on a single line
---@param line_text string
---@return table[] list of {col_start=number, col_end=number} (0-indexed byte columns)
local function parse_words(line_text)
  local words = {}
  local pos = 1
  while pos <= #line_text do
    local s, e = line_text:find("%S+", pos)
    if not s then
      break
    end
    words[#words + 1] = { col_start = s - 1, col_end = e }
    pos = e + 1
  end
  return words
end

--- Highlight the current word, dim everything else
---@param buf number
---@param line number 0-indexed
---@param col_start number 0-indexed
---@param col_end number byte position (exclusive for extmark)
local function highlight_word(buf, line, col_start, col_end)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  local line_count = vim.api.nvim_buf_line_count(buf)
  if line_count > 0 then
    vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
      end_row = line_count,
      hl_group = "ReaderDim",
      hl_eol = true,
      priority = 200,
    })
  end

  vim.api.nvim_buf_set_extmark(buf, ns, line, col_start, {
    end_row = line,
    end_col = col_end,
    hl_group = "ReaderAutoScroll",
    priority = 210,
  })
end

--- Find a blank line near the given line to park the cursor on
---@param buf number
---@param near_line number 0-indexed
---@return number 0-indexed line
local function find_blank_line(buf, near_line)
  local line_count = vim.api.nvim_buf_line_count(buf)
  -- Search forward then backward for a blank line
  for offset = 1, line_count do
    local fwd = near_line + offset
    if fwd < line_count then
      local text = vim.api.nvim_buf_get_lines(buf, fwd, fwd + 1, false)[1] or ""
      if text:match("^%s*$") then
        return fwd
      end
    end
    local bwd = near_line - offset
    if bwd >= 0 then
      local text = vim.api.nvim_buf_get_lines(buf, bwd, bwd + 1, false)[1] or ""
      if text:match("^%s*$") then
        return bwd
      end
    end
  end
  -- No blank line found; fall back to line 0
  return 0
end

--- Find the next line with at least one word
---@param buf number
---@param from_line number 0-indexed, exclusive
---@return number|nil 0-indexed line
local function next_nonempty_line(buf, from_line)
  local line_count = vim.api.nvim_buf_line_count(buf)
  for i = from_line + 1, line_count - 1 do
    local text = vim.api.nvim_buf_get_lines(buf, i, i + 1, false)[1] or ""
    if text:match("%S") then
      return i
    end
  end
  return nil
end

--- Advance to the next word. Returns false at end of buffer.
---@return boolean
local function advance()
  if not active or not current_buf then
    return false
  end

  if word_idx < #words_on_line then
    word_idx = word_idx + 1
  else
    local next_line = next_nonempty_line(current_buf, word_line)
    if not next_line then
      return false
    end
    word_line = next_line
    local text = vim.api.nvim_buf_get_lines(current_buf, word_line, word_line + 1, false)[1] or ""
    words_on_line = parse_words(text)
    word_idx = 1
  end
  return true
end

local function on_tick()
  vim.schedule(function()
    if not active then
      return
    end

    local ok = advance()
    if not ok then
      M.stop()
      require("reader.util").notify("reader.nvim: Auto-scroll reached end", vim.log.levels.INFO)
      return
    end

    local word = words_on_line[word_idx]
    highlight_word(current_buf, word_line, word.col_start, word.col_end)

    -- Park cursor on a blank line so it doesn't overlap the highlighted word
    parked_line = find_blank_line(current_buf, word_line)
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_cursor(win, { parked_line + 1, 0 })

    -- Scroll viewport to keep the highlighted word visible
    local win_height = vim.api.nvim_win_get_height(win)
    local target = word_line + 1 -- 1-indexed
    local topline = math.max(1, target - math.floor(win_height / 2))
    vim.fn.winrestview({ topline = topline })
  end)
end

---@param state ReaderState
function M.start(state)
  if active then
    return
  end

  local cfg = require("reader.config").get()
  local wpm = cfg.auto_scroll_wpm or 200
  local interval_ms = math.floor(60000 / wpm)

  current_buf = state.buf
  active = true
  state.auto_scroll_active = true

  local win = vim.api.nvim_get_current_win()
  local pos = vim.api.nvim_win_get_cursor(win)
  word_line = pos[1] - 1
  local cursor_col = pos[2]

  local text = vim.api.nvim_buf_get_lines(current_buf, word_line, word_line + 1, false)[1] or ""
  words_on_line = parse_words(text)

  if #words_on_line == 0 then
    local next_line = next_nonempty_line(current_buf, word_line)
    if not next_line then
      active = false
      state.auto_scroll_active = false
      require("reader.util").notify("reader.nvim: No text to scroll", vim.log.levels.INFO)
      return
    end
    word_line = next_line
    text = vim.api.nvim_buf_get_lines(current_buf, word_line, word_line + 1, false)[1] or ""
    words_on_line = parse_words(text)
    word_idx = 1
  else
    word_idx = 1
    for i, w in ipairs(words_on_line) do
      if w.col_start >= cursor_col then
        word_idx = i
        break
      end
      word_idx = i
    end
  end

  require("reader.highlight").clear(current_buf)

  -- Hide cursor — ensure the highlight group exists even if hide_cursor is disabled
  if vim.o.termguicolors then
    vim.api.nvim_set_hl(0, "ReaderCursor", { nocombine = true, blend = 100 })
  end
  saved_guicursor = vim.go.guicursor
  vim.go.guicursor = "a:ReaderCursor/ReaderCursor"

  M.setup_highlights()

  local word = words_on_line[word_idx]
  highlight_word(current_buf, word_line, word.col_start, word.col_end)

  -- Park cursor on a blank line so it doesn't overlap the highlighted word
  parked_line = find_blank_line(current_buf, word_line)
  vim.api.nvim_win_set_cursor(win, { parked_line + 1, 0 })

  local win_height = vim.api.nvim_win_get_height(win)
  local target = word_line + 1
  local topline = math.max(1, target - math.floor(win_height / 2))
  vim.fn.winrestview({ topline = topline })

  require("reader.util").notify("reader.nvim: Auto-scroll started", vim.log.levels.INFO)

  timer = vim.uv.new_timer()
  timer:start(interval_ms, interval_ms, on_tick)
end

function M.stop()
  if not active then
    return
  end

  active = false

  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end

  -- Move cursor back to the current word before restoring visibility
  local restore_line = word_line
  local restore_col = words_on_line and words_on_line[word_idx] and words_on_line[word_idx].col_start or 0
  local win = vim.api.nvim_get_current_win()
  if restore_line then
    vim.api.nvim_win_set_cursor(win, { restore_line + 1, restore_col })
  end

  -- Restore cursor visibility
  if saved_guicursor then
    vim.go.guicursor = "a:"
    vim.go.guicursor = saved_guicursor
    saved_guicursor = nil
  end

  if current_buf and vim.api.nvim_buf_is_valid(current_buf) then
    vim.api.nvim_buf_clear_namespace(current_buf, ns, 0, -1)
  end

  local state = require("reader")._state
  if state then
    state.auto_scroll_active = false
    local cfg = require("reader.config").get()
    if cfg.use_dimtext then
      require("reader.highlight").dim_all(state.buf)
    else
      require("reader.navigate").update_focus(state)
    end
  end

  current_buf = nil
  words_on_line = nil
  word_line = nil
  word_idx = nil
  parked_line = nil

  require("reader.util").notify("reader.nvim: Auto-scroll stopped", vim.log.levels.INFO)
end

---@param state ReaderState
function M.toggle(state)
  if active then
    M.stop()
  else
    M.start(state)
  end
end

function M.is_active()
  return active
end

function M.clear(buf)
  if active then
    M.stop()
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
end

return M
