local M = {}

-- UI helpers for notifications and confirms.

-- Notify with a consistent title.
function M.notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "stem" })
end

-- Prompt a confirm dialog.
function M.confirm(prompt, choices, default)
  return vim.fn.confirm(prompt, choices, default)
end

return M
