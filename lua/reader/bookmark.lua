local M = {}

local data_path = vim.fn.stdpath("data") .. "/reader.nvim/bookmarks.lua"

---@type table<string, {chapter: number|nil, line: number, marks: table[]|nil}>
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

--- Serialize a value to a Lua literal string
---@param val any
---@param indent string
---@return string
local function serialize(val, indent)
  indent = indent or "  "
  if type(val) == "string" then
    return string.format("%q", val)
  elseif type(val) == "number" then
    return tostring(val)
  elseif type(val) == "boolean" then
    return tostring(val)
  elseif type(val) == "nil" then
    return "nil"
  elseif type(val) == "table" then
    local parts = {}
    local next_indent = indent .. "  "
    -- Check if it's an array-like table
    local is_array = #val > 0
    if is_array then
      for _, v in ipairs(val) do
        parts[#parts + 1] = next_indent .. serialize(v, next_indent)
      end
    end
    for k, v in pairs(val) do
      if not (is_array and type(k) == "number" and k >= 1 and k <= #val) then
        local key_str
        if type(k) == "string" and k:match("^[%a_][%w_]*$") then
          key_str = k
        else
          key_str = "[" .. serialize(k, next_indent) .. "]"
        end
        parts[#parts + 1] = next_indent .. key_str .. " = " .. serialize(v, next_indent)
      end
    end
    return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. indent .. "}"
  end
  return "nil"
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
  for path, entry in pairs(bookmarks) do
    f:write("  [" .. string.format("%q", path) .. "] = " .. serialize(entry) .. ",\n")
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
  if not bm[key] then
    bm[key] = {}
  end
  bm[key].chapter = chapter
  bm[key].line = line
  save()
end

--- Get saved reading position
---@param filepath string
---@return {chapter: number|nil, line: number, marks: table[]|nil}|nil
function M.get(filepath)
  local bm = load()
  local key = vim.fn.fnamemodify(filepath, ":p")
  return bm[key]
end

--- Add a user bookmark for a file
---@param filepath string
---@param chapter number|nil
---@param line number 1-based cursor line
---@param label string
function M.add_mark(filepath, chapter, line, label)
  local bm = load()
  local key = vim.fn.fnamemodify(filepath, ":p")
  if not bm[key] then
    bm[key] = { line = 1 }
  end
  if not bm[key].marks then
    bm[key].marks = {}
  end
  table.insert(bm[key].marks, { chapter = chapter, line = line, label = label })
  -- Sort marks by chapter then line
  table.sort(bm[key].marks, function(a, b)
    local ac = a.chapter or 0
    local bc = b.chapter or 0
    if ac ~= bc then
      return ac < bc
    end
    return a.line < b.line
  end)
  save()
end

--- Remove a user bookmark by index
---@param filepath string
---@param index number 1-based
function M.remove_mark(filepath, index)
  local bm = load()
  local key = vim.fn.fnamemodify(filepath, ":p")
  if not bm[key] or not bm[key].marks then
    return
  end
  table.remove(bm[key].marks, index)
  if #bm[key].marks == 0 then
    bm[key].marks = nil
  end
  save()
end

--- Get all user bookmarks for a file
---@param filepath string
---@return table[] marks sorted by chapter/line
function M.get_marks(filepath)
  local bm = load()
  local key = vim.fn.fnamemodify(filepath, ":p")
  if not bm[key] or not bm[key].marks then
    return {}
  end
  return bm[key].marks
end

--- Sort notes by chapter then line
---@param notes table[]
local function sort_notes(notes)
  table.sort(notes, function(a, b)
    local ac = a.chapter or 0
    local bc = b.chapter or 0
    if ac ~= bc then
      return ac < bc
    end
    return a.line < b.line
  end)
end

--- Add a note for a file
---@param filepath string
---@param chapter number|nil
---@param line number 1-based cursor line
---@param text string
function M.add_note(filepath, chapter, line, text)
  local bm = load()
  local key = vim.fn.fnamemodify(filepath, ":p")
  if not bm[key] then
    bm[key] = { line = 1 }
  end
  if not bm[key].notes then
    bm[key].notes = {}
  end
  table.insert(bm[key].notes, { chapter = chapter, line = line, text = text })
  sort_notes(bm[key].notes)
  save()
end

--- Remove a note by index
---@param filepath string
---@param index number 1-based
function M.remove_note(filepath, index)
  local bm = load()
  local key = vim.fn.fnamemodify(filepath, ":p")
  if not bm[key] or not bm[key].notes then
    return
  end
  table.remove(bm[key].notes, index)
  if #bm[key].notes == 0 then
    bm[key].notes = nil
  end
  save()
end

--- Get all notes for a file
---@param filepath string
---@return table[]
function M.get_notes(filepath)
  local bm = load()
  local key = vim.fn.fnamemodify(filepath, ":p")
  if not bm[key] or not bm[key].notes then
    return {}
  end
  return bm[key].notes
end

return M
