local M = {}

local cache_dir = vim.fn.stdpath("cache") .. "/reader.nvim"

---@param filepath string
---@return string
local function cache_path(filepath)
  local abs = vim.fn.fnamemodify(filepath, ":p")
  return cache_dir .. "/" .. vim.fn.sha256(abs)
end

---@param val any
---@return string
local function serialize(val)
  local t = type(val)
  if t == "string" then
    return string.format("%q", val)
  elseif t == "number" or t == "boolean" then
    return tostring(val)
  elseif t == "nil" then
    return "nil"
  elseif t == "table" then
    local parts = {}
    local n = #val
    for i = 1, n do
      parts[#parts + 1] = serialize(val[i])
    end
    for k, v in pairs(val) do
      if type(k) == "string" then
        parts[#parts + 1] = "[" .. string.format("%q", k) .. "]=" .. serialize(v)
      elseif type(k) == "number" and (k < 1 or k > n or k ~= math.floor(k)) then
        parts[#parts + 1] = "[" .. k .. "]=" .. serialize(v)
      end
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "nil"
end

---@param filepath string
---@return table|nil
function M.load(filepath)
  local cp = cache_path(filepath)

  local mf = io.open(cp .. ".meta", "r")
  if not mf then
    return nil
  end
  local cached_mtime = mf:read("*l")
  mf:close()

  local stat = vim.uv.fs_stat(filepath)
  if not stat or tostring(stat.mtime.sec) ~= cached_mtime then
    return nil
  end

  local chunk = loadfile(cp .. ".lua")
  if not chunk then
    return nil
  end
  local ok, data = pcall(chunk)
  return ok and data or nil
end

---@param filepath string
---@param data table
function M.save(filepath, data)
  vim.fn.mkdir(cache_dir, "p")
  local cp = cache_path(filepath)

  local df = io.open(cp .. ".lua", "w")
  if not df then
    return
  end
  df:write("return ")
  df:write(serialize(data))
  df:close()

  local stat = vim.uv.fs_stat(filepath)
  if not stat then
    return
  end
  local mf = io.open(cp .. ".meta", "w")
  if not mf then
    return
  end
  mf:write(tostring(stat.mtime.sec))
  mf:close()
end

return M
