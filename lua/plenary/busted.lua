local dirname = function(p)
  return vim.fn.fnamemodify(p, ":h")
end

local function get_trace(element, level, msg)
  local function trimTrace(info)
    local index = info.traceback:find "\n%s*%[C]"
    info.traceback = info.traceback:sub(1, index)
    return info
  end
  level = level or 3

  local thisdir = dirname(debug.getinfo(1, "Sl").source, ":h")
  local info = debug.getinfo(level, "Sl")
  while
    info.what == "C"
    or info.short_src:match "luassert[/\\].*%.lua$"
    or (info.source:sub(1, 1) == "@" and thisdir == dirname(info.source))
  do
    level = level + 1
    info = debug.getinfo(level, "Sl")
  end

  info.traceback = debug.traceback("", level)
  info.message = msg

  local file = false
  return file and file.getTrace(file.name, info) or trimTrace(info)
end

local is_headless = require("plenary.nvim_meta").is_headless

-- We are shadowing print so people can reliably print messages
print = function(...)
  for _, v in ipairs { ... } do
    io.stdout:write(tostring(v))
    io.stdout:write "\t"
  end

  io.stdout:write "\r\n"
end

local mod = {}

local colors = {
  pass = 32,
  fail = 91,
  err = 35,
  start = 34,
  suite = 36,
  file = 35,
  summary = 36,
}

local function color(code, text)
  return string.format("\27[%sm%s\27[0m", code, text)
end

local function time_tag()
  local sec, usec = vim.loop.gettimeofday()
  local ms = math.floor(usec / 1000)
  return os.date("%H:%M:%S", sec) .. "." .. string.format("%03d", ms)
end

local function time_prefix()
  return "[" .. time_tag() .. "] "
end

local results = {}
local current_description = {}
local current_before_each = {}
local current_after_each = {}

local add_description = function(desc)
  table.insert(current_description, desc)

  return vim.deepcopy(current_description)
end

local pop_description = function()
  current_description[#current_description] = nil
end

local add_new_each = function()
  current_before_each[#current_description] = {}
  current_after_each[#current_description] = {}
end

local clear_last_each = function()
  current_before_each[#current_description] = nil
  current_after_each[#current_description] = nil
end

local call_inner = function(desc, func)
  local desc_stack = add_description(desc)
  add_new_each()
  local ok, msg = xpcall(func, function(msg)
    local trace = get_trace(nil, 3, msg)
    return trace.message .. "\n" .. trace.traceback
  end)
  clear_last_each()
  pop_description()

  return ok, msg, desc_stack
end

local indent = function(msg, spaces)
  if spaces == nil then
    spaces = 4
  end

  local prefix = string.rep(" ", spaces)
  return prefix .. msg:gsub("\n", "\n" .. prefix)
end

local run_each = function(tbl)
  for _, v in ipairs(tbl) do
    for _, w in ipairs(v) do
      if type(w) == "function" then
        w()
      end
    end
  end
end

local test_util = nil
do
  local ok, mod = pcall(require, "tests.test_util")
  if ok then
    test_util = mod
  end
end

local function stack_to_name(desc_stack)
  return table.concat(desc_stack, " ")
end

mod.format_results = function(res, elapsed_ms)
  local summary = string.format(
    "%s %s passed, %s failed, %s errors in %dms",
    color(colors.summary, "[Summary]"),
    color(colors.pass, tostring(#res.pass)),
    color(colors.fail, tostring(#res.fail)),
    color(colors.err, tostring(#res.errs)),
    elapsed_ms
  )
  print(time_prefix() .. summary)
end

mod.describe = function(desc, func)
  results.pass = results.pass or {}
  results.fail = results.fail or {}
  results.errs = results.errs or {}

  if #current_description == 0 then
    print(time_prefix() .. string.format("%s %s", color(colors.suite, "[Suite]"), desc))
  end

  describe = mod.inner_describe
  local ok, msg, desc_stack = call_inner(desc, func)
  describe = mod.describe

  if not ok then
    table.insert(results.errs, {
      descriptions = desc_stack,
      msg = msg,
    })
  end
end

mod.inner_describe = function(desc, func)
  local ok, msg, desc_stack = call_inner(desc, func)

  if not ok then
    table.insert(results.errs, {
      descriptions = desc_stack,
      msg = msg,
    })
  end
end

mod.before_each = function(fn)
  table.insert(current_before_each[#current_description], fn)
end

mod.after_each = function(fn)
  table.insert(current_after_each[#current_description], fn)
end

mod.clear = function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
end

mod.it = function(desc, func)
  local desc_stack = vim.deepcopy(current_description)
  table.insert(desc_stack, desc)
  local name = stack_to_name(desc_stack)
  print(time_prefix() .. string.format("%s %s", color(colors.start, "[Start]"), name))
  if test_util and test_util.set_current_test then
    test_util.set_current_test(name)
  end

  local start = vim.loop.hrtime()
  run_each(current_before_each)
  local ok, msg, _ = call_inner(desc, func)
  run_each(current_after_each)
  local elapsed_ms = math.floor((vim.loop.hrtime() - start) / 1e6)
  if test_util and test_util.flush_current_test then
    test_util.flush_current_test()
  end
  if test_util and test_util.clear_current_test then
    test_util.clear_current_test()
  end

  local test_result = {
    descriptions = desc_stack,
    msg = nil,
  }

  local to_insert
  if not ok then
    to_insert = results.fail
    test_result.msg = msg
    print(time_prefix() .. string.format("%s %s (%dms)", color(colors.fail, "[Fail ]"), name, elapsed_ms))
    print(indent(msg, 9))
    print("")
  else
    to_insert = results.pass
    print(time_prefix() .. string.format("%s %s (%dms)", color(colors.pass, "[Pass ]"), name, elapsed_ms))
    print("")
  end

  table.insert(to_insert, test_result)
end

mod.pending = function(desc, func)
  local curr_stack = vim.deepcopy(current_description)
  table.insert(curr_stack, desc)
  print(string.format("  [Pend ] %s", stack_to_name(curr_stack)))
end

_PlenaryBustedOldAssert = _PlenaryBustedOldAssert or assert

describe = mod.describe
it = mod.it
pending = mod.pending
before_each = mod.before_each
after_each = mod.after_each
clear = mod.clear
---@type Luassert
assert = require "luassert"

mod.run = function(file)
  file = file:gsub("\\", "/")

  local env_file = vim.env.PLENARY_TEST_FILE
  if env_file and env_file ~= "" then
    print ""
    print(time_prefix() .. string.format("%s %s", color(colors.file, "[File ]"), env_file))
  end

  local loaded, msg = loadfile(file)

  if not loaded then
    print("FAILED TO LOAD FILE")
    print(msg)
    if is_headless then
      return vim.cmd "2cq"
    else
      return
    end
  end

  local suite_start = vim.loop.hrtime()

  coroutine.wrap(function()
    loaded()

    if not results.pass then
      if is_headless then
        return vim.cmd "0cq"
      else
        return
      end
    end

    local suite_elapsed_ms = math.floor((vim.loop.hrtime() - suite_start) / 1e6)
    mod.format_results(results, suite_elapsed_ms)

    if #results.errs ~= 0 then
      print("We had an unexpected error: ", vim.inspect(results.errs), vim.inspect(results))
      if is_headless then
        return vim.cmd "2cq"
      end
    elseif #results.fail > 0 then
      print "Tests Failed. Exit: 1"

      if is_headless then
        return vim.cmd "1cq"
      end
    else
      if is_headless then
        return vim.cmd "0cq"
      end
    end
  end)()
end

return mod
