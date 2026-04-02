local util = require("reader.util")

local M = {}

local ns = vim.api.nvim_create_namespace("reader_nvim")

function M.setup_highlights()
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local fg = normal.fg or 0xd4d4d4
  local bg = normal.bg or 0x1e1e1e
  vim.api.nvim_set_hl(0, "ReaderDim", { fg = util.blend(fg, bg, 0.35) })
end

--- Apply focus highlight: dim everything except the focused paragraph range
---@param buf number
---@param para_start number 0-indexed line
---@param para_end number 0-indexed line (inclusive)
function M.focus_paragraph(buf, para_start, para_end)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  local line_count = vim.api.nvim_buf_line_count(buf)

  -- Dim lines before the focused paragraph
  if para_start > 0 then
    vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
      end_row = para_start,
      hl_group = "ReaderDim",
      hl_eol = true,
      priority = 200,
    })
  end

  -- Dim lines after the focused paragraph
  if para_end + 1 < line_count then
    vim.api.nvim_buf_set_extmark(buf, ns, para_end + 1, 0, {
      end_row = line_count,
      hl_group = "ReaderDim",
      hl_eol = true,
      priority = 200,
    })
  end
end

--- Dim all text in the buffer
---@param buf number
function M.dim_all(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local line_count = vim.api.nvim_buf_line_count(buf)
  if line_count > 0 then
    vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
      end_row = line_count,
      hl_group = "ReaderDim",
      hl_eol = true,
      priority = 200,
    })
  end
end

function M.clear(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
end

return M
