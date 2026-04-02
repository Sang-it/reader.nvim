local M = {}

--- Blend two RGB colors
---@param fg number
---@param bg number
---@param alpha number 0..1 (0=all bg, 1=all fg)
---@return number
function M.blend(fg, bg, alpha)
  local r1, g1, b1 = math.floor(fg / 65536), math.floor(fg / 256) % 256, fg % 256
  local r2, g2, b2 = math.floor(bg / 65536), math.floor(bg / 256) % 256, bg % 256
  local r = math.floor(r1 * alpha + r2 * (1 - alpha))
  local g = math.floor(g1 * alpha + g2 * (1 - alpha))
  local b = math.floor(b1 * alpha + b2 * (1 - alpha))
  return r * 65536 + g * 256 + b
end

--- Show a message that auto-clears after 2s in zen mode, or uses vim.notify otherwise
---@param msg string
---@param level number|nil vim.log.levels value
function M.notify(msg, level)
  local cfg = require("reader.config").get()
  if cfg.zen_mode then
    local hl = "Comment"
    if level == vim.log.levels.ERROR then
      hl = "ErrorMsg"
    elseif level == vim.log.levels.WARN then
      hl = "WarningMsg"
    end
    vim.api.nvim_echo({ { msg, hl } }, false, {})
    vim.defer_fn(function()
      vim.api.nvim_echo({ { "" } }, false, {})
    end, 2000)
  else
    vim.notify(msg, level)
  end
end

return M
