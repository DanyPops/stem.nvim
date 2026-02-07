local Path = require "plenary.path"
local Job = require "plenary.job"

local f = require "plenary.functional"
local log = require "plenary.log"
local win_float = require "plenary.window.float"

local headless = require("plenary.nvim_meta").is_headless

local plenary_dir = vim.fn.fnamemodify(debug.getinfo(1).source:match "@?(.*[/\\])", ":p:h:h:h")

local harness = {}

local function color(code, text)
  return string.format("\27[%sm%s\27[0m", code, text)
end

local summary_colors = {
  label = 36,
  pass = 32,
  fail = 91,
  err = 35,
}

local function time_tag()
  local sec, usec = vim.loop.gettimeofday()
  local ms = math.floor(usec / 1000)
  return os.date("%H:%M:%S", sec) .. "." .. string.format("%03d", ms)
end

local function time_prefix()
  return "[" .. time_tag() .. "] "
end

local print_output = vim.schedule_wrap(function(_, ...)
  for _, v in ipairs { ... } do
    io.stdout:write(tostring(v))
    io.stdout:write "\n"
  end

  vim.cmd [[mode]]
end)

local get_nvim_output = function(job_id)
  return vim.schedule_wrap(function(bufnr, ...)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    for _, v in ipairs { ... } do
      vim.api.nvim_chan_send(job_id, v .. "\r\n")
    end
  end)
end

function harness.test_directory_command(command)
  local split_string = vim.split(command, " ")
  local directory = vim.fn.expand(table.remove(split_string, 1))

  local opts = assert(loadstring("return " .. table.concat(split_string, " ")))()

  return harness.test_directory(directory, opts)
end

local function test_paths(paths, opts)
  local minimal = not opts or not opts.init or opts.minimal or opts.minimal_init

  opts = vim.tbl_deep_extend("force", {
    nvim_cmd = vim.v.progpath,
    winopts = { winblend = 3 },
    sequential = false,
    keep_going = true,
    timeout = 50000,
  }, opts or {})

  vim.env.PLENARY_TEST_TIMEOUT = opts.timeout

  local res = {}
  local totals = { pass = 0, fail = 0, err = 0, ms = 0 }
  if not headless then
    res = win_float.percentage_range_window(0.95, 0.70, opts.winopts)

    res.job_id = vim.api.nvim_open_term(res.bufnr, {})
    vim.api.nvim_buf_set_keymap(res.bufnr, "n", "q", ":q<CR>", {})

    vim.api.nvim_win_set_option(res.win_id, "winhl", "Normal:Normal")
    vim.api.nvim_win_set_option(res.win_id, "conceallevel", 3)
    vim.api.nvim_win_set_option(res.win_id, "concealcursor", "n")

    if res.border_win_id then
      vim.api.nvim_win_set_option(res.border_win_id, "winhl", "Normal:Normal")
    end

    if res.bufnr then
      vim.api.nvim_buf_set_option(res.bufnr, "filetype", "PlenaryTestPopup")
    end
    vim.cmd "mode"
  end

  local outputter = headless and print_output or get_nvim_output(res.job_id)

  local function parse_summary_line(line)
    if type(line) ~= "string" then
      return nil
    end
    local clean = line:gsub("\r", ""):gsub("%s+$", "")
    local pass, fail, err, ms = clean:match("^PLENARY_SUMMARY|(%d+)|(%d+)|(%d+)|(%d+)$")
    if not pass then
      return nil
    end
    return tonumber(pass), tonumber(fail), tonumber(err), tonumber(ms)
  end

  local function normalize_lines(data)
    if type(data) == "table" then
      return data
    end
    if data == nil then
      return {}
    end
    return { data }
  end

  local function handle_lines(lines, should_output)
    for _, line in ipairs(normalize_lines(lines)) do
      local clean = line
      if type(clean) == "string" then
        clean = clean:gsub("\r", "")
      end
      if clean == nil or clean == "" then
        if should_output then
          outputter(res.bufnr, clean)
        end
      else
        local pass, fail, err, ms = parse_summary_line(clean)
        if pass then
          totals.pass = totals.pass + pass
          totals.fail = totals.fail + fail
          totals.err = totals.err + err
          totals.ms = totals.ms + ms
        elseif should_output then
          outputter(res.bufnr, clean)
        end
      end
    end
  end

  local path_len = #paths
  local failure = false

  local base_env = vim.fn.environ()
  local jobs = vim.tbl_map(function(p)
    local args = {
      "--headless",
      "-c",
      "set rtp+=.," .. vim.fn.escape(plenary_dir, " ") .. " | runtime plugin/plenary.vim",
    }

    if minimal then
      table.insert(args, "--noplugin")
      if opts.minimal_init then
        table.insert(args, "-u")
        table.insert(args, opts.minimal_init)
      end
    elseif opts.init ~= nil then
      table.insert(args, "-u")
      table.insert(args, opts.init)
    end

    table.insert(args, "-c")
    table.insert(args, string.format('lua require("plenary.busted").run("%s")', p:absolute():gsub("\\", "\\\\")))

    local env = vim.tbl_extend("force", base_env, {
      PLENARY_TEST_FILE = p:absolute(),
    })

    local job = Job:new {
      command = opts.nvim_cmd,
      args = args,
      env = env,

      -- Can be turned on to debug
      on_stdout = function(_, data)
        if path_len == 1 then
          handle_lines(data, true)
        end
      end,

      on_stderr = function(_, data)
        if path_len == 1 then
          handle_lines(data, true)
        end
      end,

      on_exit = vim.schedule_wrap(function(j_self, _, _)
        if path_len ~= 1 then
          handle_lines(j_self:stderr_result(), true)
          handle_lines(j_self:result(), true)
        end

        vim.cmd "mode"
      end),
    }
    job.nvim_busted_path = p.filename
    return job
  end, paths)

  log.debug "Running..."
  for i, j in ipairs(jobs) do
    j:start()
    if opts.sequential then
      log.debug("... Sequential wait for job number", i)
      if not Job.join(j, opts.timeout) then
        log.debug("... Timed out job number", i)
        failure = true
        pcall(function()
          j.handle:kill(15) -- SIGTERM
        end)
      else
        log.debug("... Completed job number", i, j.code, j.signal)
        failure = failure or j.code ~= 0 or j.signal ~= 0
      end
      if failure and not opts.keep_going then
        break
      end
    end
  end

  if not headless then
    return
  end

  if not opts.sequential then
    table.insert(jobs, opts.timeout)
    log.debug "... Parallel wait"
    Job.join(unpack(jobs))
    log.debug "... Completed jobs"
    table.remove(jobs, table.getn(jobs))
    failure = f.any(function(_, v)
      return v.code ~= 0
    end, jobs)
  end
  vim.wait(100)

  if headless then
    if totals.pass + totals.fail + totals.err > 0 then
      local summary = string.format(
        "%s %s passed, %s failed, %s errors in %dms",
        color(summary_colors.label, "[Totals]"),
        color(summary_colors.pass, tostring(totals.pass)),
        color(summary_colors.fail, tostring(totals.fail)),
        color(summary_colors.err, tostring(totals.err)),
        totals.ms
      )
      outputter(res.bufnr, time_prefix() .. summary)
    end
    if failure then
      return vim.cmd "1cq"
    end

    return vim.cmd "0cq"
  end
end

function harness.test_directory(directory, opts)
  print "Starting..."
  directory = directory:gsub("\\", "/")
  local paths = harness._find_files_to_run(directory)

  -- Paths work strangely on Windows, so lets have abs paths
  if vim.fn.has "win32" == 1 or vim.fn.has "win64" == 1 then
    paths = vim.tbl_map(function(p)
      return Path:new(directory, p.filename)
    end, paths)
  end

  test_paths(paths, opts)
end

function harness.test_file(filepath)
  test_paths { Path:new(filepath) }
end

function harness._find_files_to_run(directory)
  local finder
  if vim.fn.has "win32" == 1 or vim.fn.has "win64" == 1 then
    -- On windows use powershell Get-ChildItem instead
    local cmd = vim.fn.executable "pwsh.exe" == 1 and "pwsh" or "powershell"
    finder = Job:new {
      command = cmd,
      args = { "-NoProfile", "-Command", [[Get-ChildItem -Recurse -n -Filter "*_spec.lua"]] },
      cwd = directory,
    }
  else
    -- everywhere else use find
    finder = Job:new {
      command = "find",
      args = { directory, "-type", "f", "-name", "*_spec.lua" },
    }
  end

  return vim.tbl_map(Path.new, finder:sync(vim.env.PLENARY_TEST_TIMEOUT))
end

function harness._run_path(test_type, directory)
  local paths = harness._find_files_to_run(directory)

  local bufnr = 0
  local win_id = 0

  for _, p in pairs(paths) do
    print " "
    print("Loading Tests For: ", p:absolute(), "\n")

    local ok, _ = pcall(function()
      dofile(p:absolute())
    end)

    if not ok then
      print "Failed to load file"
    end
  end

  harness:run(test_type, bufnr, win_id)
  vim.cmd "qa!"

  return paths
end

return harness
