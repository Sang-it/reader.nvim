local M = {}

local ns = vim.api.nvim_create_namespace("reader_notes")
local hidden = false

--- Render notes as ghost text for the current chapter/buffer
---@param state ReaderState
function M.render(state)
  if not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  if hidden then
    vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
    return
  end

  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)

  local bookmark = require("reader.bookmark")
  local all_notes = bookmark.get_notes(state.filepath)
  if #all_notes == 0 then
    return
  end

  local current_chapter = state.chapters and state.current_chapter or nil
  local line_count = vim.api.nvim_buf_line_count(state.buf)

  for _, note in ipairs(all_notes) do
    local note_ch = note.chapter or nil
    -- Only render notes for the current chapter (or all if no chapters)
    if note_ch == current_chapter then
      local line = note.line - 1 -- 0-indexed
      if line >= 0 and line < line_count then
        vim.api.nvim_buf_set_extmark(state.buf, ns, line, 0, {
          virt_lines = { { { "  ~ " .. note.text, "ReaderNote" } } },
          virt_lines_above = false,
        })
      end
    end
  end
end

--- Clear all note virtual text
---@param buf number
function M.clear(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
end

--- Set up the highlight group for notes
function M.setup_highlights()
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local bg = normal.bg or 0x1e1e1e
  -- A muted accent color for notes
  local note_fg = vim.api.nvim_get_hl(0, { name = "DiagnosticInfo", link = false }).fg or 0x6fb3d2
  vim.api.nvim_set_hl(0, "ReaderNote", { fg = note_fg, italic = true })
end

--- Initialize hidden state from config
function M.init()
  local cfg = require("reader.config").get()
  hidden = not cfg.show_notes
end

--- Toggle note visibility
---@param state ReaderState
function M.toggle(state)
  hidden = not hidden
  M.render(state)
  vim.notify("reader.nvim: Notes " .. (hidden and "hidden" or "visible"), vim.log.levels.INFO)
end

--- Add a note at the current cursor position
---@param state ReaderState
function M.add_note(state)
  local bookmark = require("reader.bookmark")
  local win = vim.api.nvim_get_current_win()
  local line = vim.api.nvim_win_get_cursor(win)[1]
  local chapter = state.chapters and state.current_chapter or nil

  vim.ui.input({ prompt = "Note: " }, function(input)
    if not input or input == "" then
      return
    end
    vim.schedule(function()
      bookmark.add_note(state.filepath, chapter, line, input)
      M.render(state)
      vim.notify("reader.nvim: Note added", vim.log.levels.INFO)
    end)
  end)
end

--- Remove a note via picker
---@param state ReaderState
function M.remove_note(state)
  local bookmark = require("reader.bookmark")
  local all_notes = bookmark.get_notes(state.filepath)
  if #all_notes == 0 then
    vim.notify("reader.nvim: No notes", vim.log.levels.INFO)
    return
  end

  local items = {}
  for i, note in ipairs(all_notes) do
    local prefix = ""
    if note.chapter and state.chapters then
      local ch = state.chapters[note.chapter]
      if ch then
        prefix = string.format("[%s] ", ch.title)
      end
    end
    items[i] = string.format("%sL%d: %s", prefix, note.line, note.text)
  end

  vim.ui.select(items, { prompt = "Remove note:" }, function(_, idx)
    if not idx then
      return
    end
    vim.schedule(function()
      bookmark.remove_note(state.filepath, idx)
      M.render(state)
      vim.notify("reader.nvim: Note removed", vim.log.levels.INFO)
    end)
  end)
end

--- Jump to next note
---@param state ReaderState
function M.next_note(state)
  local bookmark = require("reader.bookmark")
  local all_notes = bookmark.get_notes(state.filepath)
  if #all_notes == 0 then
    vim.notify("reader.nvim: No notes", vim.log.levels.INFO)
    return
  end

  local chapter = state.chapters and state.current_chapter or nil
  local win = vim.api.nvim_get_current_win()
  local line = vim.api.nvim_win_get_cursor(win)[1]
  local ch = chapter or 0

  for i, note in ipairs(all_notes) do
    local nc = note.chapter or 0
    if nc > ch or (nc == ch and note.line > line) then
      -- Jump to chapter if needed
      if note.chapter and state.chapters and note.chapter ~= state.current_chapter then
        require("reader.navigate").load_chapter(state, note.chapter)
        M.render(state)
      end
      local max_line = vim.api.nvim_buf_line_count(state.buf)
      vim.api.nvim_win_set_cursor(win, { math.min(note.line, max_line), 0 })
      vim.api.nvim_echo({ { string.format("Note %d/%d: %s", i, #all_notes, note.text), "Comment" } }, false, {})
      vim.defer_fn(function() vim.api.nvim_echo({ { "" } }, false, {}) end, 2000)
      return
    end
  end
  vim.notify("reader.nvim: No next note", vim.log.levels.INFO)
end

--- Jump to previous note
---@param state ReaderState
function M.prev_note(state)
  local bookmark = require("reader.bookmark")
  local all_notes = bookmark.get_notes(state.filepath)
  if #all_notes == 0 then
    vim.notify("reader.nvim: No notes", vim.log.levels.INFO)
    return
  end

  local chapter = state.chapters and state.current_chapter or nil
  local win = vim.api.nvim_get_current_win()
  local line = vim.api.nvim_win_get_cursor(win)[1]
  local ch = chapter or 0

  for i = #all_notes, 1, -1 do
    local note = all_notes[i]
    local nc = note.chapter or 0
    if nc < ch or (nc == ch and note.line < line) then
      if note.chapter and state.chapters and note.chapter ~= state.current_chapter then
        require("reader.navigate").load_chapter(state, note.chapter)
        M.render(state)
      end
      local max_line = vim.api.nvim_buf_line_count(state.buf)
      vim.api.nvim_win_set_cursor(win, { math.min(note.line, max_line), 0 })
      vim.api.nvim_echo({ { string.format("Note %d/%d: %s", i, #all_notes, note.text), "Comment" } }, false, {})
      vim.defer_fn(function() vim.api.nvim_echo({ { "" } }, false, {}) end, 2000)
      return
    end
  end
  vim.notify("reader.nvim: No previous note", vim.log.levels.INFO)
end

--- Show all notes in a picker and jump to selected
---@param state ReaderState
function M.show_notes(state)
  local bookmark = require("reader.bookmark")
  local all_notes = bookmark.get_notes(state.filepath)
  if #all_notes == 0 then
    vim.notify("reader.nvim: No notes", vim.log.levels.INFO)
    return
  end

  local items = {}
  for i, note in ipairs(all_notes) do
    local prefix = ""
    if note.chapter and state.chapters then
      local ch_data = state.chapters[note.chapter]
      if ch_data then
        prefix = string.format("[%s] ", ch_data.title)
      end
    end
    items[i] = string.format("%sL%d: %s", prefix, note.line, note.text)
  end

  vim.ui.select(items, { prompt = "Notes:" }, function(_, idx)
    if not idx then
      return
    end
    vim.schedule(function()
      local note = all_notes[idx]
      if note.chapter and state.chapters and note.chapter ~= state.current_chapter then
        require("reader.navigate").load_chapter(state, note.chapter)
        M.render(state)
      end
      local win = vim.api.nvim_get_current_win()
      local max_line = vim.api.nvim_buf_line_count(state.buf)
      vim.api.nvim_win_set_cursor(win, { math.min(note.line, max_line), 0 })
    end)
  end)
end

return M
