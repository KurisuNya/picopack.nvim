local Utils = require('picopack.utils')

---@param fn fun()
---@param trace? PicoPack.Trace
---@return boolean success
local execute_now = function(fn, trace)
  local ok, err = Utils.pcall_with_trace(fn)
  if not ok then
    local msg = trace and ('\n\nTraceback of `' .. trace.name .. '()` call:\n' .. trace.msg) or ''
    Utils.notify(err .. msg, 'ERROR')
  end
  return ok
end

---@type {f: fun(), trace: PicoPack.Trace}[]
local later_buffer = {}

local execute_later = function()
  local timer = assert(vim.uv.new_timer())
  local f
  f = vim.schedule_wrap(function()
    local cb = later_buffer[1]
    if cb == nil then
      if not timer:is_closing() then
        timer:close()
      end
      return
    end

    table.remove(later_buffer, 1)
    execute_now(cb.f, cb.trace)
    timer:start(1, 0, f)
  end)
  -- Space out "later" executions to be sure that they don't block anything
  timer:start(1, 0, f)
end

---@param events PicoPack.EventResolved[]
---@param fn fun()
---@param trace? PicoPack.Trace
local make_defer_autocmds = function(events, fn, trace)
  local au_ids = {}
  local clear_autocmds = function()
    for _, au_id in ipairs(au_ids) do
      pcall(vim.api.nvim_del_autocmd, au_id)
    end
  end

  local cb = function()
    clear_autocmds()
    execute_now(fn, trace)
  end

  local group = vim.api.nvim_create_augroup('PicoPack.Safecall', { clear = false })
  for _, event in ipairs(events) do
    local opts = { group = group, pattern = event.pattern, callback = cb, nested = true }
    local ok, au_id = Utils.pcall_with_trace(vim.api.nvim_create_autocmd, event.name, opts)
    if not ok then
      clear_autocmds()
      local name = (trace or {}).name or 'make_defer_autocmds'
      local msg = ('cannot create autocmd: %s'):format(au_id)
      Utils.fail(name, msg)
    end
    table.insert(au_ids, au_id)
  end
end

---@param buf_id integer
---@param ft_arr string[]
---@param needs_redetect boolean
local redetect_filetypes = function(buf_id, ft_arr, needs_redetect)
  if not vim.api.nvim_buf_is_loaded(buf_id) then
    return
  end
  vim.api.nvim_buf_call(buf_id, function()
    -- Try detecting new filetypes
    if needs_redetect and vim.bo.buftype == '' then
      vim.cmd('filetype detect')
    end
    -- Force execution of 'ftplugin' scripts for matched filetypes
    if vim.tbl_contains(ft_arr, vim.bo.filetype) then
      vim.bo.filetype = vim.bo.filetype
    end
  end)
end

local M = {}

---@param fn fun()
---@return boolean success
M.now = function(fn) return execute_now(fn) end

---@param fn fun()
M.later = function(fn)
  local trace = { name = 'safecall.later', msg = debug.traceback('', 2) }
  if #later_buffer == 0 then
    vim.schedule(execute_later)
  end
  table.insert(later_buffer, { f = fn, trace = trace })
end

---@param events PicoPack.EventResolved[]
---@param fn fun()
M.when_events = function(events, fn)
  if #events == 0 then
    return
  end

  local trace = { name = 'safecall.when_events', msg = debug.traceback('', 2) }
  make_defer_autocmds(events, fn, trace)
end

---@param filetypes string[]
---@param fn fun()
M.when_filetypes = function(filetypes, fn)
  if #filetypes == 0 then
    return
  end

  local trace = { name = 'safecall.when_filetypes', msg = debug.traceback('', 2) }
  -- NOTE: Needs `vim.schedule_wrap()` for a correct redetect. This also
  -- prompts using `execute_now` and not rely on `make_defer_autocmds`.
  local f_and_redetect = vim.schedule_wrap(function()
    -- Look out for new 'ftdetect' scripts by comparing before and after
    local ftdetect_scripts_before = vim.api.nvim_get_runtime_file('ftdetect/*.{vim,lua}', true)
    local ok = execute_now(fn, trace)
    -- Skip redetect if there was error or detection is disabled
    if not (ok and vim.g.did_load_filetypes == 1) then
      return
    end
    local ftdetect_scripts_after = vim.api.nvim_get_runtime_file('ftdetect/*.{vim,lua}', true)
    local needs_redetect = not vim.deep_equal(ftdetect_scripts_before, ftdetect_scripts_after)
    for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
      redetect_filetypes(buf_id, filetypes, needs_redetect)
    end
  end)
  local events = { { name = { 'FileType' }, pattern = filetypes } }
  make_defer_autocmds(events, f_and_redetect, trace)
end

return M
