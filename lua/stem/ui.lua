local M = {}

function M.notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "stem" })
end

function M.confirm(prompt, choices, default)
  return vim.fn.confirm(prompt, choices, default)
end

return M
