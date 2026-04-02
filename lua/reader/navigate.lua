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
    highlight.focus_paragraph(state.buf, para.start, para.end_)
    if require("reader.config").get().center_focus then
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
      highlight.focus_paragraph(state.buf, para.start, para.end_)
      if cfg.center_focus then
        vim.cmd("normal! zz")
      end
    end
  end

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

return M
