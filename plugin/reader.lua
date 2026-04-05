vim.api.nvim_create_user_command("Reader", function(opts)
  require("reader").open(opts.fargs[1])
end, {
  nargs = "?",
  complete = "file",
  desc = "Open file in reader mode",
})

vim.api.nvim_create_user_command("ReaderClose", function()
  require("reader").close()
end, { desc = "Close reader mode" })

vim.api.nvim_create_user_command("ReaderNext", function()
  local state = require("reader")._state
  if state then
    require("reader.navigate").next_chapter(state)
  end
end, { desc = "Jump to next chapter" })

vim.api.nvim_create_user_command("ReaderPrev", function()
  local state = require("reader")._state
  if state then
    require("reader.navigate").prev_chapter(state)
  end
end, { desc = "Jump to previous chapter" })

vim.api.nvim_create_user_command("ReaderToc", function()
  local state = require("reader")._state
  if state then
    require("reader.navigate").show_toc(state)
  end
end, { desc = "Show table of contents" })

vim.api.nvim_create_user_command("ReaderMark", function()
  local state = require("reader")._state
  if state then
    require("reader.navigate").add_mark(state)
  end
end, { desc = "Add a bookmark at current position" })

vim.api.nvim_create_user_command("ReaderMarks", function()
  local state = require("reader")._state
  if state then
    require("reader.navigate").show_marks(state)
  end
end, { desc = "Show bookmarks picker" })

vim.api.nvim_create_user_command("ReaderMarkDelete", function()
  local state = require("reader")._state
  if state then
    require("reader.navigate").remove_mark(state)
  end
end, { desc = "Remove a bookmark" })

vim.api.nvim_create_user_command("ReaderNote", function()
  local state = require("reader")._state
  if state then
    require("reader.notes").add_note(state)
  end
end, { desc = "Add a note at current position" })

vim.api.nvim_create_user_command("ReaderNotes", function()
  local state = require("reader")._state
  if state then
    require("reader.notes").show_notes(state)
  end
end, { desc = "Show notes picker" })

vim.api.nvim_create_user_command("ReaderNoteDelete", function()
  local state = require("reader")._state
  if state then
    require("reader.notes").remove_note(state)
  end
end, { desc = "Remove a note" })

vim.api.nvim_create_user_command("ReaderHighlights", function()
  local state = require("reader")._state
  if state then
    require("reader.marker").show_highlights(state)
  end
end, { desc = "Show highlights picker" })

vim.api.nvim_create_user_command("ReaderHighlightDelete", function()
  local state = require("reader")._state
  if state then
    require("reader.marker").remove_highlight(state)
  end
end, { desc = "Remove a highlight" })

vim.api.nvim_create_user_command("ReaderAutoScrollToggle", function()
  local state = require("reader")._state
  if state then
    require("reader.autoscroll").toggle(state)
  end
end, { desc = "Toggle auto-scroll mode" })

vim.api.nvim_create_user_command("ReaderGo", function(opts)
  local state = require("reader")._state
  if not state then
    return
  end
  local n = tonumber(opts.fargs[1])
  if not n then
    vim.notify("reader.nvim: Usage: :ReaderGo <chapter number>", vim.log.levels.ERROR)
    return
  end
  if not state.chapters or n < 1 or n > #state.chapters then
    vim.notify(
      string.format("reader.nvim: Chapter %d out of range (1-%d)", n, state.chapters and #state.chapters or 0),
      vim.log.levels.ERROR
    )
    return
  end
  require("reader.navigate").load_chapter(state, n)
end, {
  nargs = 1,
  desc = "Jump to a specific chapter by number",
})
