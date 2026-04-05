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
local interval_ms = 300

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

--- Check if a word ends with sentence-ending punctuation
---@param line_text string
---@param word table {col_start, col_end}
---@return boolean
local function is_sentence_end(line_text, word)
  local ch = line_text:sub(word.col_end, word.col_end)
  return ch == "." or ch == "!" or ch == "?"
end

--- Highlight a single range and dim everything else
---@param buf number
---@param range table {line=number, col_start=number, col_end=number}
local function highlight_range(buf, range)
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

  vim.api.nvim_buf_set_extmark(buf, ns, range.line, range.col_start, {
    end_row = range.line,
    end_col = range.col_end,
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
local function advance_one()
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

--- Get the screen row for a buffer position (detects visual line wraps)
---@param win number
---@param lnum number 1-indexed buffer line
---@param col number 0-indexed byte column
---@return number screen row
local function screen_row(win, lnum, col)
  local pos = vim.fn.screenpos(win, lnum, col + 1) -- screenpos uses 1-indexed col
  return pos.row
end

--- Advance words on the current visual line only (up to count).
--- Stops early at sentence-ending punctuation or visual line wrap boundary.
---@param count number max words to collect
---@return table|nil range {line, col_start, col_end}, number words_collected, boolean hit_sentence_end
local function advance_line_group(count)
  local start_line = nil
  local col_start = nil
  local col_end = nil
  local collected = 0
  local hit_end = false
  local group_screen_row = nil
  local win = vim.api.nvim_get_current_win()

  for _ = 1, count do
    local prev_line = word_line
    local prev_idx = word_idx
    local prev_words = words_on_line

    if not advance_one() then
      break
    end

    local word = words_on_line[word_idx]
    local row = screen_row(win, word_line + 1, word.col_start)

    if not group_screen_row then
      group_screen_row = row
    elseif row ~= group_screen_row then
      word_line = prev_line
      word_idx = prev_idx
      words_on_line = prev_words
      break
    end

    if not start_line then
      start_line = word_line
      col_start = word.col_start
    end
    col_end = word.col_end
    collected = collected + 1

    local line_text = vim.api.nvim_buf_get_lines(current_buf, word_line, word_line + 1, false)[1] or ""
    if is_sentence_end(line_text, word) then
      hit_end = true
      break
    end
  end

  if collected == 0 then
    return nil, 0, false
  end
  return { line = start_line, col_start = col_start, col_end = col_end }, collected, hit_end
end

--- Display a range, park cursor on a blank line, and scroll viewport
---@param range table {line, col_start, col_end}
local function display_range(range)
  highlight_range(current_buf, range)

  parked_line = find_blank_line(current_buf, range.line)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_cursor(win, { parked_line + 1, 0 })

  local win_height = vim.api.nvim_win_get_height(win)
  local target = range.line + 1
  local topline = math.max(1, target - math.floor(win_height / 2))
  vim.fn.winrestview({ topline = topline })
end

-- Forward declarations for mutual recursion
local schedule_next
local show_group

--- Show a group of words, splitting across visual lines with full-interval pauses.
--- Calls schedule_next when the entire group is done.
---@param word_count number total words for the group
---@param per_word_ms number milliseconds per word (for sentence pause)
---@param sentence_pause boolean whether to add extra pause at sentence endings
show_group = function(word_count, per_word_ms, sentence_pause)
  local range, collected, hit_sentence_end = advance_line_group(word_count)
  if not range then
    M.stop()
    require("reader.util").notify("reader.nvim: Auto-scroll reached end", vim.log.levels.INFO)
    return
  end

  display_range(range)
  local remaining = word_count - collected

  if remaining > 0 and not hit_sentence_end then
    if timer then
      timer:stop()
      timer:close()
    end
    timer = vim.uv.new_timer()
    timer:start(interval_ms, 0, function()
      vim.schedule(function()
        if not active then
          return
        end
        show_group(remaining, per_word_ms, sentence_pause)
      end)
    end)
  else
    local next_delay = interval_ms
    if hit_sentence_end and sentence_pause then
      next_delay = next_delay + per_word_ms
    end
    schedule_next(next_delay)
  end
end

schedule_next = function(delay)
  if not active then
    return
  end
  if timer then
    timer:stop()
    timer:close()
  end
  timer = vim.uv.new_timer()
  timer:start(delay, 0, function()
    vim.schedule(function()
      if not active then
        return
      end
      local cfg = require("reader.config").get()
      local count = cfg.auto_scroll_words or 3
      local per_word_ms = math.floor(60000 / (cfg.auto_scroll_wpm or 200))
      show_group(count, per_word_ms, cfg.auto_scroll_sentence_pause)
    end)
  end)
end

---@param state ReaderState
function M.start(state)
  if active then
    return
  end

  local cfg = require("reader.config").get()
  local wpm = cfg.auto_scroll_wpm or 200
  local word_count = cfg.auto_scroll_words or 3
  local per_word_ms = math.floor(60000 / wpm)
  interval_ms = per_word_ms * word_count

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
    word_idx = 0
  else
    local start_idx = 1
    for i, w in ipairs(words_on_line) do
      if w.col_start >= cursor_col then
        start_idx = i
        break
      end
      start_idx = i
    end
    word_idx = start_idx - 1
  end

  require("reader.highlight").clear(current_buf)

  -- Hide cursor — ensure the highlight group exists even if hide_cursor is disabled
  if vim.o.termguicolors then
    vim.api.nvim_set_hl(0, "ReaderCursor", { nocombine = true, blend = 100 })
  end
  saved_guicursor = vim.go.guicursor
  vim.go.guicursor = "a:ReaderCursor/ReaderCursor"

  M.setup_highlights()

  -- Show initial group
  show_group(word_count, per_word_ms, cfg.auto_scroll_sentence_pause)

  require("reader.util").notify("reader.nvim: Auto-scroll started", vim.log.levels.INFO)
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
