local M = {}

-- Shared filesystem helpers for lock files.

function M.ensure_dir(path)
  vim.fn.mkdir(path, "p")
  return path
end

function M.list_dir(path)
  if vim.fn.isdirectory(path) == 0 then
    return {}
  end
  return vim.fn.readdir(path)
end

function M.list_glob(path)
  return vim.fn.globpath(path, "*", false, true)
end

function M.write_lock(path)
  vim.fn.writefile({ os.date("!%Y-%m-%dT%H:%M:%SZ") }, path)
end

function M.remove_lock(path)
  vim.fn.delete(path)
end

return M
