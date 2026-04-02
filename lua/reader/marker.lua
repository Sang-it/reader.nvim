local M = {}

local ns = vim.api.nvim_create_namespace("reader_marker")

--- Set up the highlight group
function M.setup_highlights()
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local bg = normal.bg or 0x1e1e1e
  local hl_bg = vim.api.nvim_get_hl(0, { name = "Visual", link = false }).bg or 0x264f78
  vim.api.nvim_set_hl(0, "ReaderMarker", { bg = hl_bg })
end

--- Render all highlights for the current chapter/buffer
---@param state ReaderState
function M.render(state)
  if not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)

  local bookmark = require("reader.bookmark")
  local all_hl = bookmark.get_highlights(state.filepath)
  if #all_hl == 0 then
    return
  end

  local current_chapter = state.chapters and state.current_chapter or nil
  local line_count = vim.api.nvim_buf_line_count(state.buf)

  for _, hl in ipairs(all_hl) do
    local hl_ch = hl.chapter or nil
    if hl_ch == current_chapter then
      local sl = hl.start_line - 1 -- 0-indexed
      local el = hl.end_line - 1
      if sl >= 0 and sl < line_count then
        el = math.min(el, line_count - 1)
        if sl == el then
          -- Single line highlight
          vim.api.nvim_buf_set_extmark(state.buf, ns, sl, hl.start_col, {
            end_row = el,
            end_col = hl.end_col,
            hl_group = "ReaderMarker",
            priority = 150,
          })
        else
          -- Multi-line highlight
          vim.api.nvim_buf_set_extmark(state.buf, ns, sl, hl.start_col, {
            end_row = el,
            end_col = hl.end_col,
            hl_group = "ReaderMarker",
            priority = 150,
          })
        end
      end
    end
  end
end

--- Clear all marker extmarks
---@param buf number
function M.clear(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
end

--- Add a highlight from visual selection
---@param state ReaderState
function M.add_highlight(state)
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

  -- Get the selected text for preview
  local lines = vim.api.nvim_buf_get_lines(state.buf, sl - 1, el, false)
  if #lines == 0 then
    return
  end

  local text
  if #lines == 1 then
    text = lines[1]:sub(sc + 1, ec)
  else
    lines[1] = lines[1]:sub(sc + 1)
    lines[#lines] = lines[#lines]:sub(1, ec)
    text = table.concat(lines, " ")
  end
  if #text > 60 then
    text = text:sub(1, 57) .. "..."
  end

  local chapter = state.chapters and state.current_chapter or nil

  -- Exit visual mode
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)

  bookmark.add_highlight(state.filepath, chapter, sl, sc, el, ec, text)
  M.render(state)
  vim.notify("reader.nvim: Highlight added", vim.log.levels.INFO)
end

--- Remove a highlight via picker
---@param state ReaderState
function M.remove_highlight(state)
  local bookmark = require("reader.bookmark")
  local all_hl = bookmark.get_highlights(state.filepath)
  if #all_hl == 0 then
    vim.notify("reader.nvim: No highlights", vim.log.levels.INFO)
    return
  end

  local items = {}
  for i, hl in ipairs(all_hl) do
    local prefix = ""
    if hl.chapter and state.chapters then
      local ch = state.chapters[hl.chapter]
      if ch then
        prefix = string.format("[%s] ", ch.title)
      end
    end
    items[i] = string.format("%sL%d: %s", prefix, hl.start_line, hl.text)
  end

  vim.ui.select(items, { prompt = "Remove highlight:" }, function(_, idx)
    if not idx then
      return
    end
    vim.schedule(function()
      bookmark.remove_highlight(state.filepath, idx)
      M.render(state)
      vim.notify("reader.nvim: Highlight removed", vim.log.levels.INFO)
    end)
  end)
end

--- Jump to next highlight
---@param state ReaderState
function M.next_highlight(state)
  local bookmark = require("reader.bookmark")
  local all_hl = bookmark.get_highlights(state.filepath)
  if #all_hl == 0 then
    vim.notify("reader.nvim: No highlights", vim.log.levels.INFO)
    return
  end

  local chapter = state.chapters and state.current_chapter or nil
  local win = vim.api.nvim_get_current_win()
  local line = vim.api.nvim_win_get_cursor(win)[1]
  local ch = chapter or 0

  for i, hl in ipairs(all_hl) do
    local hc = hl.chapter or 0
    if hc > ch or (hc == ch and hl.start_line > line) then
      if hl.chapter and state.chapters and hl.chapter ~= state.current_chapter then
        require("reader.navigate").load_chapter(state, hl.chapter)
        M.render(state)
      end
      local max_line = vim.api.nvim_buf_line_count(state.buf)
      vim.api.nvim_win_set_cursor(win, { math.min(hl.start_line, max_line), hl.start_col })
      vim.api.nvim_echo({ { string.format("Highlight %d/%d: %s", i, #all_hl, hl.text), "Comment" } }, false, {})
      vim.defer_fn(function() vim.api.nvim_echo({ { "" } }, false, {}) end, 2000)
      return
    end
  end
  vim.notify("reader.nvim: No next highlight", vim.log.levels.INFO)
end

--- Jump to previous highlight
---@param state ReaderState
function M.prev_highlight(state)
  local bookmark = require("reader.bookmark")
  local all_hl = bookmark.get_highlights(state.filepath)
  if #all_hl == 0 then
    vim.notify("reader.nvim: No highlights", vim.log.levels.INFO)
    return
  end

  local chapter = state.chapters and state.current_chapter or nil
  local win = vim.api.nvim_get_current_win()
  local line = vim.api.nvim_win_get_cursor(win)[1]
  local ch = chapter or 0

  for i = #all_hl, 1, -1 do
    local hl = all_hl[i]
    local hc = hl.chapter or 0
    if hc < ch or (hc == ch and hl.start_line < line) then
      if hl.chapter and state.chapters and hl.chapter ~= state.current_chapter then
        require("reader.navigate").load_chapter(state, hl.chapter)
        M.render(state)
      end
      local max_line = vim.api.nvim_buf_line_count(state.buf)
      vim.api.nvim_win_set_cursor(win, { math.min(hl.start_line, max_line), hl.start_col })
      vim.api.nvim_echo({ { string.format("Highlight %d/%d: %s", i, #all_hl, hl.text), "Comment" } }, false, {})
      vim.defer_fn(function() vim.api.nvim_echo({ { "" } }, false, {}) end, 2000)
      return
    end
  end
  vim.notify("reader.nvim: No previous highlight", vim.log.levels.INFO)
end

--- Show all highlights in a picker and jump to selected
---@param state ReaderState
function M.show_highlights(state)
  local bookmark = require("reader.bookmark")
  local all_hl = bookmark.get_highlights(state.filepath)
  if #all_hl == 0 then
    vim.notify("reader.nvim: No highlights", vim.log.levels.INFO)
    return
  end

  local items = {}
  for i, hl in ipairs(all_hl) do
    local prefix = ""
    if hl.chapter and state.chapters then
      local ch_data = state.chapters[hl.chapter]
      if ch_data then
        prefix = string.format("[%s] ", ch_data.title)
      end
    end
    items[i] = string.format("%sL%d: %s", prefix, hl.start_line, hl.text)
  end

  vim.ui.select(items, { prompt = "Highlights:" }, function(_, idx)
    if not idx then
      return
    end
    vim.schedule(function()
      local hl = all_hl[idx]
      if hl.chapter and state.chapters and hl.chapter ~= state.current_chapter then
        require("reader.navigate").load_chapter(state, hl.chapter)
        M.render(state)
      end
      local win = vim.api.nvim_get_current_win()
      local max_line = vim.api.nvim_buf_line_count(state.buf)
      vim.api.nvim_win_set_cursor(win, { math.min(hl.start_line, max_line), hl.start_col })
    end)
  end)
end

return M
