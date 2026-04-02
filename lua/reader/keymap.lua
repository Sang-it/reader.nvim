local M = {}

local cursor_hidden = false
local saved_guicursor = nil

local function hide_cursor()
  if not cursor_hidden then
    vim.go.guicursor = "a:ReaderCursor/ReaderCursor"
    cursor_hidden = true
  end
end

local function show_cursor()
  if cursor_hidden then
    vim.go.guicursor = "a:"
    vim.go.guicursor = saved_guicursor or ""
    cursor_hidden = false
  end
end

local function update_cursor_visibility()
  if not saved_guicursor then
    return
  end

  local cfg = require("reader.config").get()

  if cfg.hide_cursor == "always" then
    hide_cursor()
    return
  end

  -- "whitespace" mode: hide on blank lines (between paragraphs)
  local line = vim.api.nvim_get_current_line()
  if line:match("^%s*$") then
    hide_cursor()
  else
    show_cursor()
  end
end

--- Set up shared keymaps (quit, chapters, bookmarks)
---@param buf number
---@param state ReaderState
local function attach_shared(buf, state)
  local cfg = require("reader.config").get()
  local opts = { buffer = buf, noremap = true, silent = true }
  local nav = require("reader.navigate")

  vim.keymap.set("n", cfg.keys.quit, function()
    require("reader").close()
  end, opts)

  if state.chapters then
    if cfg.keys.next_chapter then
      vim.keymap.set("n", cfg.keys.next_chapter, function()
        nav.next_chapter(state)
      end, opts)
    end
    if cfg.keys.prev_chapter then
      vim.keymap.set("n", cfg.keys.prev_chapter, function()
        nav.prev_chapter(state)
      end, opts)
    end
    if cfg.keys.toc then
      vim.keymap.set("n", cfg.keys.toc, function()
        nav.show_toc(state)
      end, opts)
    end
  end

  -- Bookmark keymaps
  if cfg.keys.add_mark then
    vim.keymap.set("n", cfg.keys.add_mark, function()
      nav.add_mark(state)
    end, opts)
  end
  if cfg.keys.remove_mark then
    vim.keymap.set("n", cfg.keys.remove_mark, function()
      nav.remove_mark(state)
    end, opts)
  end
  if cfg.keys.next_mark then
    vim.keymap.set("n", cfg.keys.next_mark, function()
      nav.next_mark(state)
    end, opts)
  end
  if cfg.keys.prev_mark then
    vim.keymap.set("n", cfg.keys.prev_mark, function()
      nav.prev_mark(state)
    end, opts)
  end
  if cfg.keys.list_marks then
    vim.keymap.set("n", cfg.keys.list_marks, function()
      nav.show_marks(state)
    end, opts)
  end

  -- Note keymaps
  local notes = require("reader.notes")
  if cfg.keys.add_note then
    vim.keymap.set("n", cfg.keys.add_note, function()
      notes.add_note(state)
    end, opts)
  end
  if cfg.keys.remove_note then
    vim.keymap.set("n", cfg.keys.remove_note, function()
      notes.remove_note(state)
    end, opts)
  end
  if cfg.keys.next_note then
    vim.keymap.set("n", cfg.keys.next_note, function()
      notes.next_note(state)
    end, opts)
  end
  if cfg.keys.prev_note then
    vim.keymap.set("n", cfg.keys.prev_note, function()
      notes.prev_note(state)
    end, opts)
  end
  if cfg.keys.list_notes then
    vim.keymap.set("n", cfg.keys.list_notes, function()
      notes.show_notes(state)
    end, opts)
  end
  if cfg.keys.toggle_notes then
    vim.keymap.set("n", cfg.keys.toggle_notes, function()
      notes.toggle(state)
    end, opts)
  end

  -- Highlight keymaps
  local marker = require("reader.marker")
  if cfg.keys.add_highlight then
    vim.keymap.set("v", cfg.keys.add_highlight, function()
      marker.add_highlight(state)
    end, opts)
  end
  if cfg.keys.remove_highlight then
    vim.keymap.set("n", cfg.keys.remove_highlight, function()
      marker.remove_highlight(state)
    end, opts)
  end
  if cfg.keys.next_highlight then
    vim.keymap.set("n", cfg.keys.next_highlight, function()
      marker.next_highlight(state)
    end, opts)
  end
  if cfg.keys.prev_highlight then
    vim.keymap.set("n", cfg.keys.prev_highlight, function()
      marker.prev_highlight(state)
    end, opts)
  end
  if cfg.keys.list_highlights then
    vim.keymap.set("n", cfg.keys.list_highlights, function()
      marker.show_highlights(state)
    end, opts)
  end
end

---@param buf number
---@param state ReaderState
function M.attach(buf, state)
  -- Store original guicursor for cursor hide/restore
  local s = require("reader.buffer")._saved[buf]
  if s and s.opts.guicursor then
    saved_guicursor = s.opts.guicursor
  end

  attach_shared(buf, state)

  local group = vim.api.nvim_create_augroup("ReaderCursorTrack", { clear = true })
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    group = group,
    callback = function()
      require("reader.navigate").update_focus(state)
      update_cursor_visibility()
    end,
  })

  update_cursor_visibility()
  state._augroup = group
end

---@param buf number
---@param state ReaderState
function M.attach_minimal(buf, state)
  attach_shared(buf, state)
end

function M.detach_minimal(state)
  -- No augroup or cursor state to clean up
end

function M.detach(state)
  if state._augroup then
    vim.api.nvim_del_augroup_by_id(state._augroup)
    state._augroup = nil
  end
  show_cursor()
  if saved_guicursor then
    vim.cmd.redrawstatus()
  end
  saved_guicursor = nil
end

return M
