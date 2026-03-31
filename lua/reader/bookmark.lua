local M = {}

local data_path = vim.fn.stdpath("data") .. "/reader.nvim/bookmarks.lua"

---@type table<string, {chapter: number|nil, line: number}>
local bookmarks = nil

--- Load bookmarks from disk
---@return table
local function load()
  if bookmarks then
    return bookmarks
  end
  local chunk = loadfile(data_path)
  if chunk then
    local ok, data = pcall(chunk)
    if ok and type(data) == "table" then
      bookmarks = data
      return bookmarks
    end
  end
  bookmarks = {}
  return bookmarks
end

--- Save bookmarks to disk
local function save()
  if not bookmarks then
    return
  end
  local dir = vim.fn.fnamemodify(data_path, ":h")
  vim.fn.mkdir(dir, "p")
  local f = io.open(data_path, "w")
  if not f then
    return
  end
  f:write("return {\n")
  for path, pos in pairs(bookmarks) do
    f:write(string.format("  [%q] = { chapter = %s, line = %d },\n", path, pos.chapter or "nil", pos.line))
  end
  f:write("}\n")
  f:close()
end

--- Save current reading position
---@param filepath string
---@param chapter number|nil
---@param line number 1-based cursor line
function M.set(filepath, chapter, line)
  local bm = load()
  local key = vim.fn.fnamemodify(filepath, ":p")
  bm[key] = { chapter = chapter, line = line }
  save()
end

--- Get saved reading position
---@param filepath string
---@return {chapter: number|nil, line: number}|nil
function M.get(filepath)
  local bm = load()
  local key = vim.fn.fnamemodify(filepath, ":p")
  return bm[key]
end

return M
