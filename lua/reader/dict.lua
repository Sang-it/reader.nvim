local M = {}

local ns = vim.api.nvim_create_namespace("reader_dict")
local active_buf = nil
local active_line = nil
local active_col_start = nil
local active_col_end = nil

--- Clear dictionary ghost text
function M.clear()
  if active_buf and vim.api.nvim_buf_is_valid(active_buf) then
    vim.api.nvim_buf_clear_namespace(active_buf, ns, 0, -1)
  end
  active_buf = nil
  active_line = nil
  active_col_start = nil
  active_col_end = nil
end

--- Set up highlight group
function M.setup_highlights()
  local util = require("reader.util")
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local bg = normal.bg or 0x1e1e1e
  local fg = vim.api.nvim_get_hl(0, { name = "DiagnosticHint", link = false }).fg or 0x8ec07c
  local dimmed = util.blend(fg, bg, 0.5)
  vim.api.nvim_set_hl(0, "ReaderDict", { fg = dimmed, italic = true })
  vim.api.nvim_set_hl(0, "ReaderDictArrow", { fg = dimmed })
  vim.api.nvim_set_hl(0, "ReaderDictWord", { underline = true, sp = dimmed })
end

--- Parse dict.org response into a single definition string
---@param data string[]
---@return string
local function parse_definition(data)
  local lines = {}
  local in_def = false
  local seen_def = false

  for _, line in ipairs(data) do
    line = line:gsub("\r", "")
    if line:match("^552 ") then
      return "No definition found"
    elseif line:match("^151 ") then
      in_def = true
      seen_def = true
    elseif line:match("^%.%s*$") then
      if in_def then
        in_def = false
        break -- stop after first definition
      end
    elseif line:match("^250 ") then
      if seen_def then
        break
      end
    elseif in_def then
      if not line:match("^%d%d%d ") then
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed and #trimmed > 0 then
          lines[#lines + 1] = trimmed
        end
      end
    end
  end

  if #lines == 0 then
    return "No definition found"
  end

  -- Join into single line, take first meaningful definition
  local result = table.concat(lines, " ")
  -- Clean up dict markup
  result = result:gsub("%{(.-)%}", "%1")
  result = result:gsub("%[.-%]", "")
  result = result:gsub("\\(.-)\\", "%1")
  result = result:gsub("%s+", " ")
  result = result:match("^%s*(.-)%s*$")

  if #result > 120 then
    result = result:sub(1, 117) .. "..."
  end

  return result
end

--- Look up a word and display definition as inline ghost text
---@param state ReaderState
function M.lookup(state)
  -- Get visual selection
  local sl = vim.fn.line("v")
  local sc = vim.fn.col("v") - 1
  local el = vim.fn.line(".")
  local ec = vim.fn.col(".")

  if sl > el or (sl == el and sc > ec) then
    sl, el = el, sl
    sc, ec = ec, sc
  end

  -- Only support single-line selections for dict
  if sl ~= el then
    return
  end

  local buf_line = vim.api.nvim_buf_get_lines(state.buf, sl - 1, sl, false)[1] or ""
  local word = buf_line:sub(sc + 1, ec)
  word = word:match("^%s*(.-)%s*$")
  if not word or #word == 0 then
    return
  end

  -- Exit visual mode
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)

  M.clear()
  active_buf = state.buf
  active_line = sl
  active_col_start = sc
  active_col_end = ec

  -- Underline the word
  vim.api.nvim_buf_set_extmark(state.buf, ns, sl - 1, sc, {
    end_row = sl - 1,
    end_col = ec,
    hl_group = "ReaderDictWord",
    priority = 170,
  })

  -- Show loading
  vim.api.nvim_buf_set_extmark(state.buf, ns, sl - 1, ec, {
    virt_text = {
      { " <- ", "ReaderDictArrow" },
      { "[ looking up... ]", "ReaderDict" },
    },
    virt_text_pos = "inline",
    id = 9999,
  })

  -- Async dict lookup
  local escaped = word:gsub("[^%w%-]", ""):lower()
  vim.fn.jobstart({ "curl", "-s", "-m", "5", "dict://dict.org/d:" .. escaped }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      vim.schedule(function()
        if active_buf ~= state.buf or active_line ~= sl then
          return
        end
        if not vim.api.nvim_buf_is_valid(state.buf) then
          return
        end

        local definition = parse_definition(data)

        -- Clear and re-render: underline + inline definition
        vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)

        vim.api.nvim_buf_set_extmark(state.buf, ns, sl - 1, sc, {
          end_row = sl - 1,
          end_col = ec,
          hl_group = "ReaderDictWord",
          priority = 170,
        })

        vim.api.nvim_buf_set_extmark(state.buf, ns, sl - 1, ec, {
          virt_text = {
            { " <- ", "ReaderDictArrow" },
            { "[ " .. definition .. " ]", "ReaderDict" },
          },
          virt_text_pos = "inline",
        })
      end)
    end,
  })
end

--- Called on CursorMoved to clear dict when cursor leaves the word
function M.on_cursor_moved()
  if not active_buf or not active_line then
    return
  end
  local win = vim.api.nvim_get_current_win()
  local pos = vim.api.nvim_win_get_cursor(win)
  local cursor_line = pos[1]
  local cursor_col = pos[2]

  if cursor_line ~= active_line
    or cursor_col < active_col_start
    or cursor_col >= active_col_end then
    M.clear()
  end
end

return M
