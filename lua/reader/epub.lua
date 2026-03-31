local M = {}

--- Extract a single file from a ZIP/EPUB archive using the system `unzip` command.
---@param archive string path to the .epub file
---@param entry string path within the archive
---@return string|nil content
local function zip_extract(archive, entry)
  local cmd = string.format("unzip -p %s %s", vim.fn.shellescape(archive), vim.fn.shellescape(entry))
  local handle = io.popen(cmd, "r")
  if not handle then
    return nil
  end
  local content = handle:read("*a")
  handle:close()
  if not content or content == "" then
    return nil
  end
  return content
end

--- Convert HTML to plain text
---@param html string
---@return string[]
function M.html_to_text(html)
  local text = html
  text = text:gsub("<head.-</head>", "")
  text = text:gsub("<script.-</script>", "")
  text = text:gsub("<style.-</style>", "")

  -- Convert headings to markdown
  for level = 1, 6 do
    local prefix = string.rep("#", level) .. " "
    text = text:gsub(
      "<[hH]" .. level .. "[^>]*>(.-)</[hH]" .. level .. ">",
      "\n\n" .. prefix .. "%1\n\n"
    )
  end

  -- Convert block elements to newlines
  text = text:gsub("<br[^>]*/?>", "\n")
  text = text:gsub("</p>", "\n\n")
  text = text:gsub("<p[^>]*>", "")
  text = text:gsub("</div>", "\n")
  text = text:gsub("<div[^>]*>", "")
  text = text:gsub("</li>", "\n")
  text = text:gsub("<li[^>]*>", "  - ")
  text = text:gsub("<hr[^>]*/?>", "\n---\n")

  -- Strip remaining tags
  text = text:gsub("<[^>]+>", "")

  -- Decode HTML entities
  local entities = {
    ["&amp;"] = "&",
    ["&lt;"] = "<",
    ["&gt;"] = ">",
    ["&quot;"] = '"',
    ["&apos;"] = "'",
    ["&nbsp;"] = " ",
    ["&mdash;"] = "--",
    ["&ndash;"] = "-",
    ["&hellip;"] = "...",
    ["&lsquo;"] = "'",
    ["&rsquo;"] = "'",
    ["&ldquo;"] = '"',
    ["&rdquo;"] = '"',
  }
  for entity, char in pairs(entities) do
    text = text:gsub(entity, char)
  end
  text = text:gsub("&#(%d+);", function(n)
    local num = tonumber(n)
    if num and num < 128 then
      return string.char(num)
    end
    return ""
  end)
  text = text:gsub("&#x(%x+);", function(n)
    local num = tonumber(n, 16)
    if num and num < 128 then
      return string.char(num)
    end
    return ""
  end)

  -- Collapse excessive blank lines
  text = text:gsub("\n%s*\n%s*\n", "\n\n")
  local lines = {}
  for line in text:gmatch("[^\n]*") do
    lines[#lines + 1] = line:match("^%s*(.-)%s*$")
  end

  -- Remove leading/trailing empty lines
  while #lines > 0 and lines[1] == "" do
    table.remove(lines, 1)
  end
  while #lines > 0 and lines[#lines] == "" do
    table.remove(lines)
  end

  return lines
end

--- Strip XML tags to get plain text content
---@param xml string
---@return string
local function xml_text(xml)
  return xml:gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", "")
end

--- Parse NCX table of contents (EPUB2)
--- Returns ordered list of {title, src} where src is the content file path
---@param ncx string NCX XML content
---@param base_dir string directory prefix for resolving relative paths
---@return table[]
local function parse_ncx(ncx, base_dir)
  local toc = {}

  -- Extract navPoints with their playOrder to ensure correct ordering
  -- Pattern: match each navPoint, get its playOrder, navLabel/text, and content src
  for navpoint in ncx:gmatch("<navPoint[^>]*>(.-)</navPoint>") do
    local label = navpoint:match("<navLabel>.-<text>(.-)</text>.-</navLabel>")
    local src = navpoint:match('<content[^>]+src="([^"]+)"')
    if label and src then
      local title = xml_text(label)
      -- Strip fragment identifier (#section) — we load the whole file
      local file_src = src:match("^([^#]+)") or src
      file_src = base_dir .. file_src
      -- URL decode
      file_src = file_src:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
      end)
      toc[#toc + 1] = { title = title, src = file_src }
    end
  end

  return toc
end

--- Parse EPUB3 nav document
---@param nav_html string nav XHTML content
---@param base_dir string
---@return table[]
local function parse_nav(nav_html, base_dir)
  local toc = {}

  -- Find the <nav epub:type="toc"> section
  local toc_nav = nav_html:match('<nav[^>]*epub:type="toc"[^>]*>(.-)</nav>')
  if not toc_nav then
    -- Try without namespace
    toc_nav = nav_html:match('<nav[^>]*type="toc"[^>]*>(.-)</nav>')
  end
  if not toc_nav then
    return toc
  end

  -- Extract <a href="...">title</a> entries
  for href, title_html in toc_nav:gmatch('<a[^>]+href="([^"]+)"[^>]*>(.-)</a>') do
    local title = xml_text(title_html)
    local file_src = href:match("^([^#]+)") or href
    file_src = base_dir .. file_src
    file_src = file_src:gsub("%%(%x%x)", function(hex)
      return string.char(tonumber(hex, 16))
    end)
    if title ~= "" then
      toc[#toc + 1] = { title = title, src = file_src }
    end
  end

  return toc
end

--- Parse an EPUB file
---@param filepath string
---@return {chapters: table[], title: string|nil}
function M.parse(filepath)
  -- Step 1: Find container.xml
  local container = zip_extract(filepath, "META-INF/container.xml")
  if not container then
    error("Invalid EPUB: missing META-INF/container.xml")
  end

  -- Step 2: Find OPF rootfile path
  local opf_path = container:match('full%-path="([^"]+)"')
  if not opf_path then
    error("Invalid EPUB: cannot find rootfile in container.xml")
  end

  local opf_dir = opf_path:match("(.*/)") or ""

  -- Step 3: Extract and parse OPF
  local opf = zip_extract(filepath, opf_path)
  if not opf then
    error("Invalid EPUB: cannot extract " .. opf_path)
  end

  local title = opf:match("<dc:title[^>]*>(.-)</dc:title>")

  -- Build manifest: id -> {href, media}
  local manifest = {}
  for item in opf:gmatch("<item[^>]+>") do
    local id = item:match('id="([^"]+)"')
    local href = item:match('href="([^"]+)"')
    local media = item:match('media%-type="([^"]+)"')
    local props = item:match('properties="([^"]+)"')
    if id and href then
      manifest[id] = { href = href, media = media or "", properties = props or "" }
    end
  end

  -- Step 4: Get TOC from NCX (EPUB2) or nav document (EPUB3)
  local toc = {}

  -- Try EPUB3 nav document first (look for properties="nav" in manifest)
  for _, item in pairs(manifest) do
    if item.properties:match("nav") then
      local nav_html = zip_extract(filepath, opf_dir .. item.href)
      if nav_html then
        toc = parse_nav(nav_html, opf_dir)
      end
      break
    end
  end

  -- Fall back to NCX (EPUB2)
  if #toc == 0 then
    -- Find NCX in manifest (media-type application/x-dtbncx+xml)
    for _, item in pairs(manifest) do
      if item.media == "application/x-dtbncx+xml" then
        local ncx = zip_extract(filepath, opf_dir .. item.href)
        if ncx then
          toc = parse_ncx(ncx, opf_dir)
        end
        break
      end
    end
  end

  -- Step 5: Build chapters from TOC entries
  -- Deduplicate consecutive entries pointing to the same file — merge them
  local chapters = {}
  local seen_files = {}

  for _, entry in ipairs(toc) do
    -- Skip if we already have a chapter for this exact file
    if not seen_files[entry.src] then
      seen_files[entry.src] = true
      local html = zip_extract(filepath, entry.src)
      if html then
        local lines = M.html_to_text(html)
        if #lines > 0 then
          chapters[#chapters + 1] = {
            title = entry.title,
            lines = lines,
          }
        end
      end
    end
  end

  -- Fallback: if no TOC or TOC produced no chapters, use spine order
  if #chapters == 0 then
    local spine = {}
    for idref in opf:gmatch('<itemref[^>]+idref="([^"]+)"') do
      spine[#spine + 1] = idref
    end

    for idx, idref in ipairs(spine) do
      local item = manifest[idref]
      if item and item.media:match("html") then
        local full_path = opf_dir .. item.href
        full_path = full_path:gsub("%%(%x%x)", function(hex)
          return string.char(tonumber(hex, 16))
        end)
        local html = zip_extract(filepath, full_path)
        if html then
          local lines = M.html_to_text(html)
          if #lines > 0 then
            -- Try to extract title from first heading
            local ch_title = lines[1]:match("^#+ (.+)")
            chapters[#chapters + 1] = {
              title = ch_title or ("Section " .. idx),
              lines = lines,
            }
          end
        end
      end
    end
  end

  return {
    chapters = chapters,
    title = title,
  }
end

return M
