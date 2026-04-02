local highlight = require("reader.highlight")

local M = {}

--- Detect paragraph boundaries from a list of lines
---@param lines string[]
---@return table[] list of {start=number, end_=number} (0-indexed)
function M.detect_paragraphs(lines)
  local paragraphs = {}
  local i = 0
  local n = #lines

  while i < n do
    -- Skip blank lines
    while i < n and lines[i + 1]:match("^%s*$") do
      i = i + 1
    end
    if i >= n then
      break
    end

    local start = i
    -- Consume non-blank lines (the paragraph)
    while i < n and not lines[i + 1]:match("^%s*$") do
      i = i + 1
    end
    table.insert(paragraphs, { start = start, end_ = i - 1 })
  end

  return paragraphs
end

--- Find which paragraph the cursor is in (or nearest to)
---@param paragraphs table[]
---@param cursor_line number 0-indexed
---@return number index (1-based)
function M.find_current(paragraphs, cursor_line)
  for i, p in ipairs(paragraphs) do
    if cursor_line >= p.start and cursor_line <= p.end_ then
      return i
    end
    if cursor_line < p.start then
      return i
    end
  end
  return #paragraphs
end

--- Update focus based on current cursor position
---@param state ReaderState
function M.update_focus(state)
  local win = vim.api.nvim_get_current_win()
  local cursor_line = vim.api.nvim_win_get_cursor(win)[1] - 1

  local index = M.find_current(state.paragraphs, cursor_line)
  if index == state.current_index then
    return
  end

  state.current_index = index
  local para = state.paragraphs[index]
  if para then
    local cfg = require("reader.config").get()
    if cfg.focus_paragraph then
      highlight.focus_paragraph(state.buf, para.start, para.end_)
    end
    if cfg.center_focus then
      vim.cmd("normal! zz")
    end
  end
end

--- Load a specific chapter into the buffer by index
---@param state ReaderState
---@param chapter_index number 1-based
function M.load_chapter(state, chapter_index)
  if not state.chapters or chapter_index < 1 or chapter_index > #state.chapters then
    return false
  end

  local buffer = require("reader.buffer")
  local bookmark = require("reader.bookmark")
  local chapter = state.chapters[chapter_index]
  state.current_chapter = chapter_index
  state.all_lines = chapter.lines

  -- Persist chapter position immediately so it survives unexpected exits
  bookmark.set(state.filepath, chapter_index, 1)

  -- Replace buffer content
  buffer.set_lines(state.buf, 0, -1, chapter.lines)

  -- Recompute paragraphs for this chapter
  state.paragraphs = M.detect_paragraphs(chapter.lines)
  state.current_index = 1

  -- Focus first paragraph
  if #state.paragraphs > 0 then
    local para = state.paragraphs[1]
    local cfg = require("reader.config").get()
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_cursor(win, { para.start + 1, 0 })
    if cfg.zen_mode then
      if cfg.focus_paragraph then
        highlight.focus_paragraph(state.buf, para.start, para.end_)
      end
      if cfg.center_focus then
        vim.cmd("normal! zz")
      end
    end
  end

  -- Re-render notes and highlights for the new chapter
  require("reader.notes").render(state)
  require("reader.marker").render(state)

  local total = #state.chapters
  local msg = string.format("%s (%d/%d)", chapter.title, chapter_index, total)
  vim.api.nvim_echo({ { msg, "Comment" } }, false, {})
  vim.defer_fn(function()
    vim.api.nvim_echo({ { "" } }, false, {})
  end, 2000)
  return true
end

--- Jump to the next chapter
---@param state ReaderState
function M.next_chapter(state)
  if not state.chapters then
    return
  end
  local next_idx = (state.current_chapter or 1) + 1
  if next_idx > #state.chapters then
    vim.notify("reader.nvim: Last chapter", vim.log.levels.INFO)
    return
  end
  M.load_chapter(state, next_idx)
end

--- Jump to the previous chapter
---@param state ReaderState
function M.prev_chapter(state)
  if not state.chapters then
    return
  end
  local prev_idx = (state.current_chapter or 1) - 1
  if prev_idx < 1 then
    vim.notify("reader.nvim: First chapter", vim.log.levels.INFO)
    return
  end
  M.load_chapter(state, prev_idx)
end

--- Show table of contents and jump to selected chapter
---@param state ReaderState
function M.show_toc(state)
  if not state.chapters then
    vim.notify("reader.nvim: No table of contents", vim.log.levels.INFO)
    return
  end
  local items = {}
  for i, ch in ipairs(state.chapters) do
    local marker = i == state.current_chapter and " *" or ""
    items[#items + 1] = ch.title .. marker
  end

  vim.ui.select(items, { prompt = "Table of Contents:" }, function(_, idx)
    if not idx then
      return
    end
    vim.schedule(function()
      M.load_chapter(state, idx)
    end)
  end)
end

--- Add a bookmark at the current cursor position
---@param state ReaderState
function M.add_mark(state)
  local bookmark = require("reader.bookmark")
  local win = vim.api.nvim_get_current_win()
  local line = vim.api.nvim_win_get_cursor(win)[1]
  local chapter = state.chapters and state.current_chapter or nil

  vim.ui.input({ prompt = "Bookmark label: " }, function(input)
    if not input or input == "" then
      return
    end
    vim.schedule(function()
      bookmark.add_mark(state.filepath, chapter, line, input)
      vim.notify("reader.nvim: Bookmark added", vim.log.levels.INFO)
    end)
  end)
end

--- Remove a bookmark via picker
---@param state ReaderState
function M.remove_mark(state)
  local bookmark = require("reader.bookmark")
  local marks = bookmark.get_marks(state.filepath)
  if #marks == 0 then
    vim.notify("reader.nvim: No bookmarks", vim.log.levels.INFO)
    return
  end

  local items = {}
  for i, mark in ipairs(marks) do
    local prefix = ""
    if mark.chapter and state.chapters then
      prefix = string.format("[Ch.%d] ", mark.chapter)
    end
    items[i] = string.format("%s%s (line %d)", prefix, mark.label, mark.line)
  end

  vim.ui.select(items, { prompt = "Remove bookmark:" }, function(_, idx)
    if not idx then
      return
    end
    vim.schedule(function()
      bookmark.remove_mark(state.filepath, idx)
      vim.notify("reader.nvim: Bookmark removed", vim.log.levels.INFO)
    end)
  end)
end

--- Find the current mark index based on cursor position
---@param marks table[]
---@param chapter number|nil
---@param line number 1-based
---@return number|nil index of current or preceding mark
local function find_current_mark(marks, chapter, line)
  local ch = chapter or 0
  local best = nil
  for i, mark in ipairs(marks) do
    local mc = mark.chapter or 0
    if mc < ch or (mc == ch and mark.line <= line) then
      best = i
    end
  end
  return best
end

--- Jump to a specific mark
---@param state ReaderState
---@param mark table {chapter, line, label}
local function goto_mark(state, mark)
  if mark.chapter and state.chapters and mark.chapter ~= state.current_chapter then
    M.load_chapter(state, mark.chapter)
  end
  local win = vim.api.nvim_get_current_win()
  local max_line = vim.api.nvim_buf_line_count(state.buf)
  local line = math.min(mark.line, max_line)
  vim.api.nvim_win_set_cursor(win, { line, 0 })

  local cfg = require("reader.config").get()
  if cfg.zen_mode then
    local index = M.find_current(state.paragraphs, line - 1)
    state.current_index = index
    if cfg.focus_paragraph then
      local para = state.paragraphs[index]
      if para then
        highlight.focus_paragraph(state.buf, para.start, para.end_)
      end
    end
    if cfg.center_focus then
      vim.cmd("normal! zz")
    end
  end
end

--- Jump to next bookmark
---@param state ReaderState
function M.next_mark(state)
  local bookmark = require("reader.bookmark")
  local marks = bookmark.get_marks(state.filepath)
  if #marks == 0 then
    vim.notify("reader.nvim: No bookmarks", vim.log.levels.INFO)
    return
  end

  local chapter = state.chapters and state.current_chapter or nil
  local win = vim.api.nvim_get_current_win()
  local line = vim.api.nvim_win_get_cursor(win)[1]
  local ch = chapter or 0

  -- Find first mark strictly after current position
  for i, mark in ipairs(marks) do
    local mc = mark.chapter or 0
    if mc > ch or (mc == ch and mark.line > line) then
      goto_mark(state, mark)
      vim.api.nvim_echo({ { string.format("Bookmark %d/%d: %s", i, #marks, mark.label), "Comment" } }, false, {})
      vim.defer_fn(function() vim.api.nvim_echo({ { "" } }, false, {}) end, 2000)
      return
    end
  end
  vim.notify("reader.nvim: No next bookmark", vim.log.levels.INFO)
end

--- Jump to previous bookmark
---@param state ReaderState
function M.prev_mark(state)
  local bookmark = require("reader.bookmark")
  local marks = bookmark.get_marks(state.filepath)
  if #marks == 0 then
    vim.notify("reader.nvim: No bookmarks", vim.log.levels.INFO)
    return
  end

  local chapter = state.chapters and state.current_chapter or nil
  local win = vim.api.nvim_get_current_win()
  local line = vim.api.nvim_win_get_cursor(win)[1]
  local ch = chapter or 0

  -- Find last mark strictly before current position
  for i = #marks, 1, -1 do
    local mark = marks[i]
    local mc = mark.chapter or 0
    if mc < ch or (mc == ch and mark.line < line) then
      goto_mark(state, mark)
      vim.api.nvim_echo({ { string.format("Bookmark %d/%d: %s", i, #marks, mark.label), "Comment" } }, false, {})
      vim.defer_fn(function() vim.api.nvim_echo({ { "" } }, false, {}) end, 2000)
      return
    end
  end
  vim.notify("reader.nvim: No previous bookmark", vim.log.levels.INFO)
end

--- Show bookmarks picker and jump to selected
---@param state ReaderState
function M.show_marks(state)
  local bookmark = require("reader.bookmark")
  local marks = bookmark.get_marks(state.filepath)
  if #marks == 0 then
    vim.notify("reader.nvim: No bookmarks", vim.log.levels.INFO)
    return
  end

  local items = {}
  for i, mark in ipairs(marks) do
    local prefix = ""
    if mark.chapter and state.chapters then
      local ch = state.chapters[mark.chapter]
      if ch then
        prefix = string.format("[%s] ", ch.title)
      end
    end
    items[i] = string.format("%s%s (line %d)", prefix, mark.label, mark.line)
  end

  vim.ui.select(items, { prompt = "Bookmarks:" }, function(_, idx)
    if not idx then
      return
    end
    vim.schedule(function()
      goto_mark(state, marks[idx])
    end)
  end)
end

return M
