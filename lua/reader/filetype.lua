local M = {}

--- Detect filetype and load content
---@param filepath string
---@return {lines: string[], chapters: table[]|nil, title: string|nil}
function M.load(filepath)
  local ext = filepath:match("%.(%w+)$")

  if ext == "epub" then
    local cache = require("reader.cache")

    -- Try cache first
    local epub_data = cache.load(filepath)
    if not epub_data then
      local epub = require("reader.epub")
      epub_data = epub.parse(filepath)
      cache.save(filepath, epub_data)
    end

    local first_lines = {}
    if #epub_data.chapters > 0 then
      first_lines = epub_data.chapters[1].lines
    end
    return {
      lines = first_lines,
      chapters = epub_data.chapters,
      title = epub_data.title,
    }
  end

  -- md, txt, or any other text file
  local loader = require("reader.loader")
  local lines = loader.read_file(filepath)
  return {
    lines = lines,
    chapters = nil,
    title = vim.fn.fnamemodify(filepath, ":t"),
  }
end

return M
