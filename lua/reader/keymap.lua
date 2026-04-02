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

---@param buf number
---@param state ReaderState
function M.attach(buf, state)
  local cfg = require("reader.config").get()
  local opts = { buffer = buf, noremap = true, silent = true }

  -- Store original guicursor for cursor hide/restore
  local s = require("reader.buffer")._saved[buf]
  if s and s.opts.guicursor then
    saved_guicursor = s.opts.guicursor
  end

  vim.keymap.set("n", cfg.keys.quit, function()
    require("reader").close()
  end, opts)

  if state.chapters then
    if cfg.keys.next_chapter then
      vim.keymap.set("n", cfg.keys.next_chapter, function()
        require("reader.navigate").next_chapter(state)
      end, opts)
    end
    if cfg.keys.prev_chapter then
      vim.keymap.set("n", cfg.keys.prev_chapter, function()
        require("reader.navigate").prev_chapter(state)
      end, opts)
    end
    if cfg.keys.toc then
      vim.keymap.set("n", cfg.keys.toc, function()
        require("reader.navigate").show_toc(state)
      end, opts)
    end
  end

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
  local cfg = require("reader.config").get()
  local opts = { buffer = buf, noremap = true, silent = true }

  vim.keymap.set("n", cfg.keys.quit, function()
    require("reader").close()
  end, opts)

  if state.chapters then
    if cfg.keys.next_chapter then
      vim.keymap.set("n", cfg.keys.next_chapter, function()
        require("reader.navigate").next_chapter(state)
      end, opts)
    end
    if cfg.keys.prev_chapter then
      vim.keymap.set("n", cfg.keys.prev_chapter, function()
        require("reader.navigate").prev_chapter(state)
      end, opts)
    end
    if cfg.keys.toc then
      vim.keymap.set("n", cfg.keys.toc, function()
        require("reader.navigate").show_toc(state)
      end, opts)
    end
  end
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
