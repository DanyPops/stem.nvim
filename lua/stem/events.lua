local M = {}

function M.new()
  local listeners = {}

  local function on(event, fn)
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
    return function()
      local list = listeners[event]
      if not list then
        return
      end
      for i, cb in ipairs(list) do
        if cb == fn then
          table.remove(list, i)
          break
        end
      end
    end
  end

  local function emit(event, payload)
    local list = listeners[event]
    if not list then
      return
    end
    for _, cb in ipairs(list) do
      cb(payload)
    end
  end

  return {
    on = on,
    emit = emit,
  }
end

return M
local M = {}

function M.new()
  local listeners = {}

  local function on(event, fn)
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
    return function()
      local list = listeners[event]
      if not list then
        return
      end
      for i, cb in ipairs(list) do
        if cb == fn then
          table.remove(list, i)
          break
        end
      end
    end
  end

  local function emit(event, payload)
    local list = listeners[event]
    if not list then
      return
    end
    for _, cb in ipairs(list) do
      cb(payload)
    end
  end

  return {
    on = on,
    emit = emit,
  }
end

return M
