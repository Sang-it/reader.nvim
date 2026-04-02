local M = {}

local ns = vim.api.nvim_create_namespace("reader_notes")
local hidden = false

--- Render notes as inline ghost text
---@param state ReaderState
function M.render(state)
  if not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)

  if hidden then
    return
  end

  local bookmark = require("reader.bookmark")
  local all_notes = bookmark.get_notes(state.filepath)
  if #all_notes == 0 then
    return
  end

  local current_chapter = state.chapters and state.current_chapter or nil
  local line_count = vim.api.nvim_buf_line_count(state.buf)

  for _, note in ipairs(all_notes) do
    local note_ch = note.chapter or nil
    if note_ch == current_chapter then
      local el = note.line - 1 -- 0-indexed
      local ec = note.col or 0
      local sl = (note.start_line or note.line) - 1
      local sc = note.start_col or 0
      if sl >= 0 and sl < line_count then
        -- Highlight the source text the note is attached to
        local end_row = math.min(el, line_count - 1)
        local end_line_text = vim.api.nvim_buf_get_lines(state.buf, end_row, end_row + 1, false)[1] or ""
        local end_col = math.min(ec, #end_line_text)
        vim.api.nvim_buf_set_extmark(state.buf, ns, sl, sc, {
          end_row = end_row,
          end_col = end_col,
          hl_group = "ReaderNoteText",
          priority = 160,
        })

        -- Inline ghost text: arrow + boxed note after the selection end
        vim.api.nvim_buf_set_extmark(state.buf, ns, end_row, end_col, {
          virt_text = {
            { " <- ", "ReaderNoteArrow" },
            { "[ " .. note.text .. " ]", "ReaderNote" },
          },
          virt_text_pos = "inline",
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

--- Blend two RGB colors
local function blend(fg, bg, alpha)
  local r1, g1, b1 = math.floor(fg / 65536), math.floor(fg / 256) % 256, fg % 256
  local r2, g2, b2 = math.floor(bg / 65536), math.floor(bg / 256) % 256, bg % 256
  local r = math.floor(r1 * alpha + r2 * (1 - alpha))
  local g = math.floor(g1 * alpha + g2 * (1 - alpha))
  local b = math.floor(b1 * alpha + b2 * (1 - alpha))
  return r * 65536 + g * 256 + b
end

--- Set up the highlight groups for notes
function M.setup_highlights()
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local bg = normal.bg or 0x1e1e1e
  local note_fg = vim.api.nvim_get_hl(0, { name = "DiagnosticInfo", link = false }).fg or 0x6fb3d2
  local dimmed = blend(note_fg, bg, 0.4)
  vim.api.nvim_set_hl(0, "ReaderNote", { fg = dimmed, italic = true })
  vim.api.nvim_set_hl(0, "ReaderNoteText", { underline = true, sp = dimmed })
  vim.api.nvim_set_hl(0, "ReaderNoteArrow", { fg = dimmed })
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

--- Add a note from visual selection
---@param state ReaderState
function M.add_note(state)
  local bookmark = require("reader.bookmark")

  -- Get visual selection range
  local sl = vim.fn.line("v")
  local sc = vim.fn.col("v") - 1
  local el = vim.fn.line(".")
  local ec = vim.fn.col(".")

  -- Normalize: ensure start is before end
  if sl > el or (sl == el and sc > ec) then
    sl, el = el, sl
    sc, ec = ec, sc
  end

  local chapter = state.chapters and state.current_chapter or nil

  -- Exit visual mode
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)

  vim.ui.input({ prompt = "Note: " }, function(input)
    if not input or input == "" then
      return
    end
    vim.schedule(function()
      bookmark.add_note(state.filepath, chapter, sl, sc, el, ec, input)
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
    local nl = note.start_line or note.line
    if nc > ch or (nc == ch and nl > line) then
      if note.chapter and state.chapters and note.chapter ~= state.current_chapter then
        require("reader.navigate").load_chapter(state, note.chapter)
        M.render(state)
      end
      local max_line = vim.api.nvim_buf_line_count(state.buf)
      local target_line = note.start_line or note.line
      vim.api.nvim_win_set_cursor(win, { math.min(target_line, max_line), note.start_col or 0 })
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
    local nl = note.start_line or note.line
    if nc < ch or (nc == ch and nl < line) then
      if note.chapter and state.chapters and note.chapter ~= state.current_chapter then
        require("reader.navigate").load_chapter(state, note.chapter)
        M.render(state)
      end
      local max_line = vim.api.nvim_buf_line_count(state.buf)
      local target_line = note.start_line or note.line
      vim.api.nvim_win_set_cursor(win, { math.min(target_line, max_line), note.start_col or 0 })
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
      local target_line = note.start_line or note.line
      vim.api.nvim_win_set_cursor(win, { math.min(target_line, max_line), note.start_col or 0 })
    end)
  end)
end

return M
