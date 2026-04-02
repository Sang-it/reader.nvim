local config = require("reader.config")

local M = {}

---@type table<number, table>
M._saved = {}

function M.create()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "reader"
  return buf
end

function M.setup_reader_mode(buf)
  local cfg = config.get()
  local saved = {}

  if not cfg.zen_mode then
    return M._setup_standard_mode(buf, cfg, saved)
  end

  -- Save and override global options
  saved.showmode = vim.o.showmode
  saved.laststatus = vim.o.laststatus
  saved.showtabline = vim.o.showtabline
  vim.o.showmode = false
  vim.o.laststatus = 0
  vim.o.showtabline = 0

  -- Backdrop: full-screen floating window behind content
  local backdrop_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[backdrop_buf].buftype = "nofile"
  local backdrop_win = vim.api.nvim_open_win(backdrop_buf, false, {
    relative = "editor",
    width = vim.o.columns,
    height = vim.o.lines,
    row = 0,
    col = 0,
    style = "minimal",
    focusable = false,
    zindex = 10,
  })
  vim.wo[backdrop_win].winhighlight = "Normal:Normal,NormalFloat:Normal"
  vim.wo[backdrop_win].fillchars = "eob: "

  -- Content: centered floating window
  local width = math.min(cfg.width, vim.o.columns - 4)
  local height = vim.o.lines - 2
  local col = math.floor((vim.o.columns - width) / 2)

  local content_win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = 0,
    col = col,
    style = "minimal",
    zindex = 20,
  })

  vim.wo[content_win].wrap = true
  vim.wo[content_win].linebreak = true
  vim.wo[content_win].cursorline = false
  vim.wo[content_win].spell = false
  vim.wo[content_win].list = false
  vim.wo[content_win].number = false
  vim.wo[content_win].relativenumber = false
  vim.wo[content_win].signcolumn = "no"
  vim.wo[content_win].foldcolumn = "0"
  vim.wo[content_win].foldenable = false
  vim.wo[content_win].statuscolumn = ""
  vim.wo[content_win].fillchars = "eob: "
  vim.wo[content_win].winhighlight = "Normal:Normal,NormalFloat:Normal"

  -- Resize handler
  local augroup = vim.api.nvim_create_augroup("ReaderResize", { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = augroup,
    callback = function()
      if not vim.api.nvim_win_is_valid(backdrop_win) then
        return
      end
      vim.api.nvim_win_set_config(backdrop_win, {
        relative = "editor",
        width = vim.o.columns,
        height = vim.o.lines,
        row = 0,
        col = 0,
      })
      if vim.api.nvim_win_is_valid(content_win) then
        local new_width = math.min(cfg.width, vim.o.columns - 4)
        vim.api.nvim_win_set_config(content_win, {
          relative = "editor",
          width = new_width,
          height = vim.o.lines - 2,
          row = 0,
          col = math.floor((vim.o.columns - new_width) / 2),
        })
      end
    end,
  })

  -- Prepare cursor hiding highlight (toggled by keymap module)
  if cfg.hide_cursor and vim.o.termguicolors then
    saved.guicursor = vim.go.guicursor
    vim.api.nvim_set_hl(0, "ReaderCursor", { nocombine = true, blend = 100 })
  end

  M._saved[buf] = {
    content_win = content_win,
    backdrop_win = backdrop_win,
    backdrop_buf = backdrop_buf,
    opts = saved,
    augroup = augroup,
  }

  return content_win
end

function M._setup_standard_mode(buf, cfg, saved)
  -- Open the reader buffer in the current window — no special options
  local prev_buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)

  M._saved[buf] = {
    content_win = win,
    prev_buf = prev_buf,
    opts = saved,
    zen_mode = false,
  }

  return win
end

function M.teardown(buf)
  local s = M._saved[buf]
  if not s then
    return
  end

  if s.zen_mode == false then
    -- Standard mode: restore the previous buffer in the window
    if s.prev_buf and vim.api.nvim_buf_is_valid(s.prev_buf) then
      if s.content_win and vim.api.nvim_win_is_valid(s.content_win) then
        vim.api.nvim_win_set_buf(s.content_win, s.prev_buf)
      end
    end
  else
    -- Zen mode: close floating windows
    if s.augroup then
      vim.api.nvim_del_augroup_by_id(s.augroup)
    end
    if s.backdrop_win and vim.api.nvim_win_is_valid(s.backdrop_win) then
      vim.api.nvim_win_close(s.backdrop_win, true)
    end
    if s.content_win and vim.api.nvim_win_is_valid(s.content_win) then
      vim.api.nvim_win_close(s.content_win, true)
    end
  end

  -- Restore global options (guicursor handled by keymap.detach)
  for k, v in pairs(s.opts) do
    if k ~= "guicursor" then
      vim.o[k] = v
    end
  end

  M._saved[buf] = nil
end

function M.set_lines(buf, start, end_, lines)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, start, end_, false, lines)
  vim.bo[buf].modifiable = false
end

return M
