local buffer = require("reader.buffer")

local M = {}

---@param buf number
---@param lines string[]
function M.load_full(buf, lines)
  buffer.set_lines(buf, 0, -1, lines)
end

---@param filepath string
---@return string[]
function M.read_file(filepath)
  local f = io.open(filepath, "r")
  if not f then
    error("Cannot open file: " .. filepath)
  end
  local lines = {}
  for line in f:lines() do
    lines[#lines + 1] = line
  end
  f:close()
  return lines
end

return M
