local config = require("reader.config")
local buffer = require("reader.buffer")
local highlight = require("reader.highlight")
local navigate = require("reader.navigate")
local loader = require("reader.loader")
local keymap = require("reader.keymap")
local filetype = require("reader.filetype")
local bookmark = require("reader.bookmark")
local notes = require("reader.notes")
local marker = require("reader.marker")
local dict = require("reader.dict")

local M = {}

---@type ReaderState|nil
M._state = nil

function M.setup(opts)
  config.setup(opts)

  local cfg = config.get()
  if cfg.auto_open and #cfg.auto_open > 0 then
    local patterns = {}
    for _, ext in ipairs(cfg.auto_open) do
      patterns[#patterns + 1] = "*." .. ext
    end
    vim.api.nvim_create_autocmd("BufEnter", {
      group = vim.api.nvim_create_augroup("ReaderAutoOpen", { clear = true }),
      pattern = patterns,
      callback = function(ev)
        if M._state then
          return
        end
        local bufname = ev.file or ""
        if bufname == "" then
          return
        end
        vim.schedule(function()
          M.open(bufname)
        end)
      end,
    })
  end
end

function M.open(filepath)
  if not filepath or filepath == "" then
    filepath = vim.api.nvim_buf_get_name(0)
    if filepath == "" then
      require("reader.util").notify("reader.nvim: No file specified", vim.log.levels.ERROR)
      return
    end
  end
  filepath = vim.fn.expand(filepath)

  if M._state then
    M.close()
  end

  local cfg = config.get()
  local zen = cfg.zen_mode

  if zen and (cfg.focus_paragraph or cfg.use_dimtext) then
    highlight.setup_highlights()
  end

  local ok, content = pcall(filetype.load, filepath)
  if not ok then
    require("reader.util").notify("reader.nvim: " .. tostring(content), vim.log.levels.ERROR)
    return
  end

  local saved_pos = bookmark.get(filepath)
  local buf = buffer.create()

  local state = {
    buf = buf,
    filepath = filepath,
    all_lines = content.lines,
    chapters = content.chapters,
    current_chapter = 1,
    paragraphs = {},
    current_index = 0,
  }

  -- Restore saved chapter for epub, or use first chapter / full file
  if saved_pos and saved_pos.chapter and state.chapters and saved_pos.chapter <= #state.chapters then
    state.current_chapter = saved_pos.chapter
    state.all_lines = state.chapters[saved_pos.chapter].lines
  end

  loader.load_full(buf, state.all_lines)
  state.paragraphs = navigate.detect_paragraphs(state.all_lines)

  if #state.paragraphs == 0 then
    require("reader.util").notify("reader.nvim: No content found", vim.log.levels.WARN)
    return
  end

  local win = buffer.setup_reader_mode(buf)
  vim.api.nvim_buf_set_name(buf, "reader://" .. (content.title or filepath))

  if zen then
    keymap.attach(buf, state)

    -- Restore saved cursor position or start at first paragraph
    if saved_pos and saved_pos.line then
      local line = math.min(saved_pos.line, vim.api.nvim_buf_line_count(buf))
      vim.api.nvim_win_set_cursor(win, { line, 0 })
      local index = navigate.find_current(state.paragraphs, line - 1)
      state.current_index = index
      if cfg.focus_paragraph and not cfg.use_dimtext then
        highlight.focus_paragraph(buf, state.paragraphs[index].start, state.paragraphs[index].end_)
      end
    else
      state.current_index = 1
      local para = state.paragraphs[1]
      if cfg.focus_paragraph and not cfg.use_dimtext then
        highlight.focus_paragraph(buf, para.start, para.end_)
      end
      vim.api.nvim_win_set_cursor(win, { para.start + 1, 0 })
    end

    if cfg.use_dimtext then
      highlight.dim_all(buf)
    end

    if cfg.center_focus then
      vim.cmd("normal! zz")
    end
  else
    -- Standard mode: just keybindings, no highlighting or cursor tricks
    keymap.attach_minimal(buf, state)

    -- Restore saved cursor position
    if saved_pos and saved_pos.line then
      local line = math.min(saved_pos.line, vim.api.nvim_buf_line_count(buf))
      vim.api.nvim_win_set_cursor(win, { line, 0 })
    end
  end

  -- Render notes and highlights
  notes.setup_highlights()
  notes.init()
  notes.render(state)
  marker.setup_highlights()
  marker.init()
  marker.render(state)
  dict.setup_highlights()
  require("reader.autoscroll").setup_highlights()

  -- Show chapter info for epub (auto-clears after 2s)
  if state.chapters and #state.chapters > 0 then
    local ch = state.chapters[state.current_chapter]
    local msg = string.format("%s (%d/%d)", ch.title, state.current_chapter, #state.chapters)
    vim.api.nvim_echo({ { msg, "Comment" } }, false, {})
    vim.defer_fn(function()
      vim.api.nvim_echo({ { "" } }, false, {})
    end, 2000)
  end

  M._state = state
end

function M.close()
  if not M._state then
    return
  end

  -- Save position before tearing down
  local win = vim.api.nvim_get_current_win()
  local line = vim.api.nvim_win_get_cursor(win)[1]
  bookmark.set(
    M._state.filepath,
    M._state.chapters and M._state.current_chapter or nil,
    line
  )

  require("reader.autoscroll").clear(M._state.buf)
  notes.clear(M._state.buf)
  marker.clear(M._state.buf)
  if config.get().zen_mode then
    highlight.clear(M._state.buf)
    keymap.detach(M._state)
  else
    keymap.detach_minimal(M._state)
  end
  buffer.teardown(M._state.buf)

  if vim.api.nvim_buf_is_valid(M._state.buf) then
    pcall(vim.api.nvim_buf_delete, M._state.buf, { force = true })
  end

  M._state = nil
end

function M.toggle()
  if M._state then
    M.close()
  else
    M.open()
  end
end

return M
